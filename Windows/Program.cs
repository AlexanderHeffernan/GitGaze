using System.Drawing;
using System.Text.Json.Nodes;
using System.Windows;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

namespace GitGaze;

internal static class Program
{
    private const string Origin = "gitgaze.local", Document = "https://" + Origin + "/dashboard.html";

    [STAThread]
    private static int Main(string[] args)
    {
        var assets = Path.Combine(AppContext.BaseDirectory, "SharedClient");
        if (args.Contains("--smoke-test"))
        {
            foreach (var file in new[] { "dashboard.html", "dashboard.css", "dashboard.js", "core.js", "activity.js", "leaderboard.js", "fixture.json", "operations.json" })
                if (!File.Exists(Path.Combine(assets, file))) return 1;
            return System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture.ToString().Equals(args.Last(), StringComparison.OrdinalIgnoreCase) ? 0 : 2;
        }
        using var singleton = new Mutex(true, "Local\\GitGaze.SharedReview", out bool started);
        if (!started) return 0;
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        using var tray = new Tray();
        using var bitmap = new Bitmap(32, 32);
        using (var graphics = Graphics.FromImage(bitmap))
        using (var pen = new Pen(Color.FromArgb(169, 143, 255), 3))
        {
            graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            graphics.DrawEllipse(pen, 5, 5, 22, 22);
            graphics.DrawArc(pen, 11, 11, 10, 10, -90, 230);
        }
        if (!tray.SetIcon(bitmap, "GitGaze · Shared-client review"))
        {
            MessageBox.Show($"Could not register GitGaze in the Windows notification area. {tray.RegistrationFailure}", "GitGaze");
            return 1;
        }
        var fixture = args.Contains("--fixture") ? JsonNode.Parse(File.ReadAllText(Path.Combine(assets, "fixture.json")))!.AsObject() : null;
        using var local = new LocalServices();
        var view = new WebView2();
        var flyout = new Window { Title = "GitGaze", Width = 384, Height = 640, ShowInTaskbar = false,
            WindowStyle = WindowStyle.None, ResizeMode = ResizeMode.NoResize, Content = view };
        var initialized = false;
        long deactivatedAt = -1000;
        flyout.Deactivated += (_, _) => { if (flyout.IsVisible) { flyout.Hide(); deactivatedAt = Environment.TickCount64; } };
        tray.Command += async (command, x, y) =>
        {
            if (command == 6) { app.Shutdown(); return; }
            if (command == 1 && (flyout.IsVisible || Environment.TickCount64 - deactivatedAt < 250))
            {
                flyout.Hide(); tray.ReturnFocus(); return;
            }
            if (command is not (1 or 2) || initialized && view.CoreWebView2 == null) return;
            if (flyout.IsVisible) { flyout.Activate(); return; }
            try
            {
                tray.Show(flyout, x, y);
                if (!initialized)
                {
                    initialized = true;
                    var userData = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "GitGaze", "SharedReviewWebView");
                    var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: userData);
                    await view.EnsureCoreWebView2Async(environment);
                    var web = view.CoreWebView2;
                    web.Settings.AreDevToolsEnabled = false;
                    web.Settings.AreDefaultContextMenusEnabled = false;
                    web.Settings.AreHostObjectsAllowed = false;
                    web.SetVirtualHostNameToFolderMapping(Origin, assets, CoreWebView2HostResourceAccessKind.Deny);
                    web.NavigationStarting += (_, e) => { if (e.Uri != Document) e.Cancel = true; };
                    web.NewWindowRequested += (_, e) => e.Handled = true;
                    web.WebMessageReceived += async (_, e) =>
                    {
                        if (e.Source != Document || e.WebMessageAsJson.Length > 4_000_000) return;
                        if (JsonNode.Parse(e.WebMessageAsJson) is not JsonObject message || message["action"] is not JsonValue action ||
                            !action.TryGetValue<string>(out var name)) return;
                        switch (name)
                        {
                            case "ready": web.PostWebMessageAsJson(fixture?.ToJsonString() ?? "{\"kind\":\"start\"}"); break;
                            case "preferences" when fixture != null: fixture["preferences"] = message["value"]?.DeepClone(); break;
                            case "request" when fixture == null && message["value"] is JsonObject call:
                                var reply = await local.Reply(call);
                                if (!app.Dispatcher.HasShutdownStarted) web.PostWebMessageAsJson(reply.ToJsonString());
                                break;
                            case "dismiss": flyout.Hide(); tray.ReturnFocus(); break;
                        }
                    };
                    web.Navigate(Document);
                }
                else await view.CoreWebView2.ExecuteScriptAsync("window.gitGazeOpen?.()");
                if (flyout.IsVisible) view.Focus();
            }
            catch (Exception ex)
            {
                flyout.Hide();
                MessageBox.Show($"Could not open the review flyout. Check the Microsoft Edge WebView2 Runtime.\n\n{ex.Message}", "GitGaze");
                app.Shutdown(1);
            }
        };
        app.Exit += (_, _) => view.Dispose();
        return app.Run();
    }
}
