using System.Diagnostics;
using System.Globalization;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace GitGaze;

// No paths, URLs, tokens or commands are supplied by the renderer.
internal sealed class LocalServices : IDisposable
{
    private readonly string directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "GitGaze");
    private readonly HttpClient http = new(new HttpClientHandler { AllowAutoRedirect = false }) { Timeout = TimeSpan.FromSeconds(30) };
    private readonly JsonObject operations = JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "SharedClient", "operations.json")))!.AsObject();
    private static readonly Regex WidgetId = new(@"\A[a-z][a-z0-9-]{0,31}\z", RegexOptions.CultureInvariant);
    private static readonly Regex Login = new(@"\A[A-Za-z0-9-]{1,39}\z", RegexOptions.CultureInvariant);
    private static readonly Regex NodeId = new(@"\A[A-Za-z0-9_+=/-]{1,256}\z", RegexOptions.CultureInvariant);
    private string? token;
    private sealed class GitHubFailure(string message, string code) : Exception(message)
    {
        public string Code => code;
    }

    public async Task<JsonObject> Reply(JsonObject call)
    {
        var reply = new JsonObject { ["id"] = call["id"]?.DeepClone() };
        try
        {
            if (call["version"]?.GetValue<int>() != 1 || call["id"]?.GetValue<int>() is not > 0)
                throw new InvalidOperationException("Unsupported bridge message.");
            reply["result"] = call["method"]?.GetValue<string>() switch
            {
                "readLocal" => new JsonObject { ["dashboard"] = Read("dashboard.json"), ["preferences"] = Read("preferences.json") ?? new JsonObject() },
                "writeCache" => Write("dashboard.json", call["args"]?.AsObject()),
                "writePreferences" => WritePreferences(call["args"]?.AsObject()),
                "github" => await GitHub(call["args"]?.AsObject()),
                _ => throw new InvalidOperationException("Unsupported host request.")
            };
        }
        catch (Exception ex)
        {
            reply["error"] = ex is GitHubFailure or InvalidOperationException ? ex.Message : "GitGaze could not complete the local or GitHub request.";
            reply["code"] = ex switch
            {
                GitHubFailure failure => failure.Code,
                TaskCanceledException => "network",
                HttpRequestException { HttpRequestError: HttpRequestError.NameResolutionError or HttpRequestError.ConnectionError } => "network",
                _ => "unknown"
            };
        }
        return reply;
    }

    private JsonNode? WritePreferences(JsonObject? changes)
    {
        if (changes == null || !changes.All(pair => pair.Key switch
        {
            "appearance" => pair.Value?.GetValue<string>() is "system" or "light" or "dark",
            "historyWeeks" => pair.Value?.GetValue<int>() is 26 or 53,
            "leaderboardPeriod" => pair.Value?.GetValue<string>() is "today" or "week" or "month" or "year",
            "reminderHour" => pair.Value?.GetValue<int>() is >= 0 and <= 23,
            "leaderboardOrganization" => pair.Value is JsonObject org && org.Count == 2 &&
                Login.IsMatch(org["account"]?.GetValue<string>() ?? "") && NodeId.IsMatch(org["id"]?.GetValue<string>() ?? ""),
            "modules" or "hidden" => pair.Value is JsonArray ids && ids.Count <= 32 &&
                ids.All(id => WidgetId.IsMatch(id?.GetValue<string>() ?? "")) && ids.Select(id => id!.GetValue<string>()).Distinct().Count() == ids.Count,
            _ => false
        })) throw new InvalidOperationException("Invalid preferences.");
        var preferences = Read("preferences.json") ?? new JsonObject();
        foreach (var (key, value) in changes) preferences[key] = value?.DeepClone();
        return Write("preferences.json", preferences);
    }

    private JsonObject? Read(string name)
    {
        try { return JsonNode.Parse(File.ReadAllText(Path.Combine(directory, name)))?.AsObject(); }
        catch (Exception ex) when (ex is FileNotFoundException or DirectoryNotFoundException or System.Text.Json.JsonException or InvalidOperationException) { return null; }
    }

    private JsonNode? Write(string name, JsonObject? data)
    {
        if (data == null) throw new InvalidOperationException("Invalid local data.");
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, name);
        var temporary = path + ".tmp";
        File.WriteAllText(temporary, data.ToJsonString());
        File.Move(temporary, path, overwrite: true);
        return null;
    }

    private async Task<JsonNode?> GitHub(JsonObject? input)
    {
        var operation = input?["operation"]?.GetValue<string>();
        string[]? required = operation switch { "viewer" => [], "following" or "leaderboardOrganizations" => ["after"], "profile" => ["login"],
            "history" => ["login", "from", "to"], "leaderboardMembers" => ["login", "org", "from", "to", "after"], _ => null };
        if (required == null || operations[operation!]?.GetValue<string>() is not string query || input?["variables"] is not JsonObject variables ||
            variables.Count != required.Length || !variables.All(pair => required.Contains(pair.Key) &&
                (pair.Value == null ? pair.Key == "after" : pair.Value.GetValue<string>().Length <= 1024)) || !ValidLeaderboard(operation!, variables))
            throw new InvalidOperationException("Unsupported GitHub request.");
        if (operation == "viewer") token = await CliToken();
        if (string.IsNullOrEmpty(token)) throw new GitHubFailure("No GitHub CLI session found. Run gh auth login --hostname github.com, then try again.", "access");
        using var request = new HttpRequestMessage(HttpMethod.Post, "https://api.github.com/graphql");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Headers.UserAgent.ParseAdd("GitGaze/1.0");
        request.Content = new StringContent(new JsonObject { ["query"] = query, ["variables"] = variables.DeepClone() }.ToJsonString(), Encoding.UTF8, "application/json");
        using var response = await http.SendAsync(request);
        if (!response.IsSuccessStatusCode)
        {
            var status = (int)response.StatusCode;
            if (response.Headers.TryGetValues("x-github-sso", out var sso) && sso.Any(value => value.StartsWith("required", StringComparison.OrdinalIgnoreCase)))
                throw new GitHubFailure("GitHub requires organization SSO authorization.", "access");
            var limited = status == 429 || status == 403 && (response.Headers.RetryAfter != null ||
                response.Headers.TryGetValues("x-ratelimit-remaining", out var remaining) && remaining.Contains("0"));
            throw new GitHubFailure($"GitHub returned HTTP {status}.", limited ? "rate_limit" : status is 401 or 403 ? "access" : status >= 500 ? "server" : "unknown");
        }
        var envelope = JsonNode.Parse(await response.Content.ReadAsStringAsync());
        if (envelope?["errors"] is JsonArray errors && errors.Count > 0)
        {
            var types = errors.Select(e => e?["type"]?.GetValue<string>()).ToArray();
            var code = types.Any(t => t is "FORBIDDEN" or "UNAUTHORIZED" or "NOT_FOUND" or "SAML_ENFORCEMENT" or "INSUFFICIENT_SCOPES") ? "access" :
                types.All(t => t == "RATE_LIMITED") ? "rate_limit" : "unknown";
            throw new GitHubFailure(errors[0]?["message"]?.GetValue<string>() ?? "GitHub rejected the request.", code);
        }
        return envelope?["data"]?.DeepClone() ?? throw new InvalidOperationException("GitHub did not return activity data.");
    }

    private static bool ValidLeaderboard(string operation, JsonObject variables)
    {
        if (operation is not ("leaderboardOrganizations" or "leaderboardMembers")) return true;
        if (variables["after"]?.GetValue<string>() is string cursor && Encoding.UTF8.GetByteCount(cursor) is not (>= 1 and <= 1024)) return false;
        if (operation == "leaderboardOrganizations") return true;
        const string format = "yyyy-MM-dd'T'HH:mm:ss.fff'Z'";
        return Login.IsMatch(variables["login"]!.GetValue<string>()) && NodeId.IsMatch(variables["org"]!.GetValue<string>()) &&
            DateTimeOffset.TryParseExact(variables["from"]!.GetValue<string>(), format, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var start) &&
            DateTimeOffset.TryParseExact(variables["to"]!.GetValue<string>(), format, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var end) &&
            end >= start && end - start <= TimeSpan.FromDays(366);
    }

    private static async Task<string?> CliToken()
    {
        // Resolve only from PATH, not the app or process working directory.
        var cli = (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator)
            .Select(path => path.Trim('"')).Where(Path.IsPathFullyQualified).Select(path => Path.Combine(path, "gh.exe")).FirstOrDefault(File.Exists);
        if (cli == null) return null;
        using var process = Process.Start(new ProcessStartInfo(cli, "auth token --hostname github.com")
        { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true });
        if (process == null) return null;
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        try
        {
            var output = process.StandardOutput.ReadToEndAsync(deadline.Token);
            var errors = process.StandardError.ReadToEndAsync(deadline.Token);
            await process.WaitForExitAsync(deadline.Token);
            await errors;
            return process.ExitCode == 0 ? (await output).Trim() : null;
        }
        catch (OperationCanceledException) { if (!process.HasExited) process.Kill(); return null; }
    }

    public void Dispose() => http.Dispose();
}
