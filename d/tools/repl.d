/**
 * selaenium REPL — the reference terminal front-end for the runner.
 *
 * The first thing a human actually USES: open a session, drive it interactively
 * with the shell language (open/click/text/eval/…) plus the debug verbs
 * (step/continue/mode/inspect), each line going down to the engine's runner
 * controller and results + events coming back up. Zero-dependency, works over
 * SSH — deliberately NOT tied to any GUI toolkit. It is one client of the runner
 * lane; an SUT-adjacent iframe or an editor host is another, over the same
 * substrate.
 *
 * Usage:
 *   repl [--browser chrome|firefox] [--url <driverOrGridUrl>]   interactive (reads stdin)
 *   repl ... < script.txt                                        batch (a line per command)
 * Lines: any shell command (`open <url>`, `text #h`, `eval <js>`, …) or a REPL
 * meta: `:step` `:continue` `:mode step|run` `:inspect trace|timers|sid` `:events`
 * plus the SAM step-aside verbs `:list` `:jump <n>` `:prev` `:next` `:redo`, and
 * `:quit`. A bare shell line is `runner.eval`'d (recorded; queued in step mode).
 *
 * Built by d/tools/.build.ae; drives the engine via the D binding's Runner.
 */
import std.stdio;
import std.string;
import std.conv : to;
import std.json;
import std.getopt;
import selenium;

int main(string[] argv) {
    string browser = "chrome";
    string url = "";
    getopt(argv, "browser", &browser, "url", &url);

    // Resolve/launch a driver unless an explicit endpoint (driver or Grid) is given.
    DriverProcess proc;
    string endpoint = url;
    if (endpoint.length == 0) {
        string drv = resolveDriver(browser);
        if (drv.length == 0) { stderr.writeln("no driver for ", browser, " (set --url for a running driver/Grid)"); return 2; }
        proc = launchDriver(drv);
        if (proc is null) { stderr.writeln("could not launch driver"); return 2; }
        endpoint = proc.url();
    }
    scope(exit) if (proc !is null) proc.stop();

    WebDriver d;
    if (browser == "firefox") d = headlessFirefox(endpoint);
    else d = headlessChrome(endpoint);
    scope(exit) d.quit();

    auto r = d.runner();
    scope(exit) r.close();
    d.setTrace(true);  // so `:inspect trace` / `:events` have something to show

    bool interactive = isTerminal();
    if (interactive) {
        writeln("selaenium repl — ", browser, " @ ", endpoint);
        writeln("shell lines drive the session; meta: :step :continue :mode :inspect :events");
        writeln("  step-aside: :list :jump <n> :prev :next :redo ; :quit");
    }

    foreach (rawLine; stdin.byLine) {
        string line = rawLine.idup.strip;
        if (line.length == 0 || line.startsWith("#")) continue;

        JSONValue rep;
        if (line == ":quit" || line == ":q") break;
        else if (line == ":step" || line == ":s") rep = r.step();
        else if (line == ":continue" || line == ":c") rep = r.cont();
        else if (line.startsWith(":mode")) rep = r.mode(line.length > 6 ? line[6 .. $].strip : "run");
        else if (line.startsWith(":inspect")) rep = r.inspect(line.length > 9 ? line[9 .. $].strip : "sid");
        else if (line == ":list" || line == ":l") rep = r.list();
        else if (line.startsWith(":jump")) rep = r.jump(line.length > 6 ? to!int(line[6 .. $].strip) : 0);
        else if (line == ":prev" || line == ":p") rep = r.prev();
        else if (line == ":next" || line == ":n") rep = r.next();
        else if (line == ":redo") rep = r.redo();
        else if (line == ":events") { drainEvents(r); continue; }
        else rep = r.eval(line);

        render(rep);
        drainEvents(r);   // show any command-finished/paused that fired
    }
    return 0;
}

/// Render a runner reply compactly: ok → its value/info, error → the message.
void render(JSONValue rep) {
    if (rep.type != JSONType.object) return;
    // runner replies wrap the shell result under "result"; unwrap one level.
    if ("result" in rep) {
        auto res = rep["result"];
        if (res.type == JSONType.object && "value" in res) { writeln(res["value"].toString()); return; }
        if (res.type == JSONType.object && "info" in res) { writeln(res["info"].str); return; }
        if (res.type == JSONType.object && "error" in res) { writeln("error: ", res["error"].str); return; }
        writeln(res.toString());
        return;
    }
    if ("error" in rep) { writeln("error: ", rep["error"].str); return; }
    // control replies (mode/step/continue) — print the object as-is.
    writeln(rep.toString());
}

/// Drain + print any pending runner events.
void drainEvents(Runner r) {
    for (;;) {
        auto ev = r.nextEvent();
        if (ev.type != JSONType.object) break;
        string m = ("method" in ev) ? ev["method"].str : "?";
        string p = ("params" in ev) ? ev["params"].toString() : "{}";
        writeln("  · ", m, " ", p);
    }
}

/// Is stdin a TTY (interactive) vs a pipe (batch)? Best-effort.
bool isTerminal() {
    version (Posix) {
        import core.sys.posix.unistd : isatty;
        return isatty(0) != 0;
    } else return false;
}
