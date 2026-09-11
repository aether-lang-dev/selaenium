// selenium.hpp — the C++ client for the shared pure-Aether WebDriver engine.
//
// A header-only RAII layer over the C client (c/include/selenium.h): C++ owns
// the handle lifetimes (WebDriver/WebElement/DriverProcess free on destruction),
// turns error codes into a WebDriverError exception, and returns std::string /
// std::optional. It carries NO protocol logic and NO JSON dependency — link the
// engine .so and the C client's selenium.c; structured results come back as
// JSON text you can feed to any JSON library.
//
// Portability: C++17, no third-party dependencies. Compile the one C TU
// (c/src/selenium.c) alongside, or link it in. Works with g++/clang++/MSVC.
//
//   #include <selenium.hpp>
//   using namespace selenium;
//   auto proc = DriverProcess::ensure("chrome");
//   WebDriver d = WebDriver::headlessChrome(proc.url());
//   d.get("https://example.com");
//   std::cout << d.title() << "\n";
//   d.findElement(By::css("a")).click();
#ifndef SELENIUM_HPP
#define SELENIUM_HPP

#include "selenium.h"

#include <string>
#include <stdexcept>
#include <optional>
#include <utility>

namespace selenium {

// A WebDriver failure. `code` is the engine's stable W3C error code (0 =
// success, -1 = transport); mirrors the C layer's sel_last_error_code.
class WebDriverError : public std::runtime_error {
public:
    int code;
    WebDriverError(int c, const std::string &msg) : std::runtime_error(msg), code(c) {}
};

// RAII wrapper turning a caller-owned sel_str into std::string (frees the sel_str).
inline std::string take(sel_str s) {
    std::string out(s.ptr ? s.ptr : "", s.len);
    sel_free(s);
    return out;
}

// A locator (strategy + value); factories mirror Selenium's By.
struct By {
    std::string strategy;
    std::string value;
    static By id(std::string v)              { return {"id", std::move(v)}; }
    static By name(std::string v)            { return {"name", std::move(v)}; }
    static By className(std::string v)       { return {"class name", std::move(v)}; }
    static By css(std::string v)             { return {"css selector", std::move(v)}; }
    static By cssSelector(std::string v)     { return {"css selector", std::move(v)}; }
    static By tagName(std::string v)         { return {"tag name", std::move(v)}; }
    static By linkText(std::string v)        { return {"link text", std::move(v)}; }
    static By partialLinkText(std::string v) { return {"partial link text", std::move(v)}; }
    static By xpath(std::string v)           { return {"xpath", std::move(v)}; }
};

class WebDriver; // fwd

// A shadow root as a search context: only find* are supported, scoped inside
// the shadow tree. Owns its underlying sel_element*.
class ShadowRoot {
public:
    explicit ShadowRoot(sel_element *e) : e_(e) {}
    ShadowRoot(ShadowRoot &&o) noexcept : e_(o.e_) { o.e_ = nullptr; }
    ShadowRoot &operator=(ShadowRoot &&o) noexcept { reset(o.e_); o.e_ = nullptr; return *this; }
    ShadowRoot(const ShadowRoot &) = delete;
    ShadowRoot &operator=(const ShadowRoot &) = delete;
    ~ShadowRoot() { if (e_) sel_element_free(e_); }

    class WebElement findElement(const By &by);

    sel_element *raw() const { return e_; }
private:
    void reset(sel_element *e) { if (e_) sel_element_free(e_); e_ = e; }
    sel_element *e_;
};

// A live element reference. Owns its sel_element*; move-only.
class WebElement {
public:
    explicit WebElement(sel_element *e) : e_(e) {}
    WebElement(WebElement &&o) noexcept : e_(o.e_) { o.e_ = nullptr; }
    WebElement &operator=(WebElement &&o) noexcept { reset(o.e_); o.e_ = nullptr; return *this; }
    WebElement(const WebElement &) = delete;
    WebElement &operator=(const WebElement &) = delete;
    ~WebElement() { if (e_) sel_element_free(e_); }

    std::string id() const { return take(sel_element_id(e_)); }

    void click()  { check(sel_click(e_), "click"); }
    void clear()  { check(sel_clear(e_), "clear"); }
    void sendKeys(const std::string &text) { check(sel_send_keys(e_, text.c_str()), "sendKeys"); }
    std::string text()           { return take(sel_text(e_)); }
    std::string tagName()        { return take(sel_tag_name(e_)); }
    std::string getAttribute(const std::string &name) { return take(sel_get_attribute(e_, name.c_str())); }
    std::string ariaRole()       { return take(sel_aria_role(e_)); }
    std::string accessibleName() { return take(sel_accessible_name(e_)); }
    bool isDisplayed() { int r = sel_is_displayed(e_); return r == 1; }
    bool isEnabled()   { int r = sel_is_enabled(e_);   return r == 1; }
    bool isSelected()  { int r = sel_is_selected(e_);  return r == 1; }

    WebElement findElement(const By &by) {
        sel_element *c = sel_find_child(e_, by.strategy.c_str(), by.value.c_str());
        if (!c) throw WebDriverError(17, "no such element: " + by.strategy + "=" + by.value);
        return WebElement(c);
    }

    // This element's shadow root; throws (code 19) if it hosts none.
    ShadowRoot shadowRoot() {
        sel_element *s = sel_shadow_root(e_);
        if (!s) throw WebDriverError(19, "no such shadow root");
        return ShadowRoot(s);
    }

    sel_element *raw() const { return e_; }
private:
    static void check(int rc, const char *what) {
        if (rc != 0) throw WebDriverError(rc, std::string("element ") + what + " failed");
    }
    void reset(sel_element *e) { if (e_) sel_element_free(e_); e_ = e; }
    sel_element *e_;
};

inline WebElement ShadowRoot::findElement(const By &by) {
    sel_element *c = sel_find_child(e_, by.strategy.c_str(), by.value.c_str());
    if (!c) throw WebDriverError(17, "no such element in shadow root");
    return WebElement(c);
}

// A running driver process (from the ported Selenium Manager). Stops on destruction.
class DriverProcess {
public:
    // Resolve + launch a driver for a browser (downloads if needed).
    static DriverProcess ensure(const std::string &browser, const std::string &hint = "", int timeoutMs = 20000) {
        sel_process *p = sel_ensure_driver(browser.c_str(), hint.empty() ? nullptr : hint.c_str(), timeoutMs);
        if (!p) throw WebDriverError(-1, "could not resolve/launch a driver for " + browser);
        return DriverProcess(p);
    }
    static DriverProcess launch(const std::string &driverPath, int timeoutMs = 20000) {
        sel_process *p = sel_launch_driver(driverPath.c_str(), timeoutMs);
        if (!p) throw WebDriverError(-1, "could not launch driver at " + driverPath);
        return DriverProcess(p);
    }

    DriverProcess(DriverProcess &&o) noexcept : p_(o.p_) { o.p_ = nullptr; }
    DriverProcess &operator=(DriverProcess &&o) noexcept { reset(o.p_); o.p_ = nullptr; return *this; }
    DriverProcess(const DriverProcess &) = delete;
    DriverProcess &operator=(const DriverProcess &) = delete;
    ~DriverProcess() { if (p_) sel_process_stop(p_); }

    std::string url() const { return take(sel_process_url(p_)); }
    int pid() const { return sel_process_pid(p_); }
    void stop() { if (p_) { sel_process_stop(p_); p_ = nullptr; } }
private:
    explicit DriverProcess(sel_process *p) : p_(p) {}
    void reset(sel_process *p) { if (p_) sel_process_stop(p_); p_ = p; }
    sel_process *p_;
};

// A live WebDriver session. Owns the sel_driver*; move-only; quits on destruction.
class WebDriver {
public:
    // --- session factories --- (optionsJson: extra caps as a JSON object, or "")
    static WebDriver chrome(const std::string &commandExecutor, const std::string &optionsJson = "") {
        return make(commandExecutor, [&](sel_driver *d) { return sel_chrome(d, opt(optionsJson)); });
    }
    static WebDriver headlessChrome(const std::string &commandExecutor) {
        return make(commandExecutor, [&](sel_driver *d) { return sel_headless_chrome(d); });
    }
    static WebDriver firefox(const std::string &commandExecutor, const std::string &optionsJson = "") {
        return make(commandExecutor, [&](sel_driver *d) { return sel_firefox(d, opt(optionsJson)); });
    }
    static WebDriver headlessFirefox(const std::string &commandExecutor) {
        return make(commandExecutor, [&](sel_driver *d) { return sel_headless_firefox(d); });
    }
    static WebDriver edge(const std::string &commandExecutor, const std::string &optionsJson = "") {
        return make(commandExecutor, [&](sel_driver *d) { return sel_edge(d, opt(optionsJson)); });
    }
    static WebDriver headlessEdge(const std::string &commandExecutor) {
        return make(commandExecutor, [&](sel_driver *d) { return sel_headless_edge(d); });
    }
    static WebDriver safari(const std::string &commandExecutor, const std::string &optionsJson = "") {
        return make(commandExecutor, [&](sel_driver *d) { return sel_safari(d, opt(optionsJson)); });
    }

    WebDriver(WebDriver &&o) noexcept : d_(o.d_) { o.d_ = nullptr; }
    WebDriver &operator=(WebDriver &&o) noexcept { reset(o.d_); o.d_ = nullptr; return *this; }
    WebDriver(const WebDriver &) = delete;
    WebDriver &operator=(const WebDriver &) = delete;
    ~WebDriver() { if (d_) { sel_execute(d_, "quit", "{}"); sel_close(d_); } }

    std::string sessionId() { return take(sel_session_id(d_)); }

    // navigation
    void get(const std::string &url) { check(sel_get(d_, url.c_str()), "get"); }
    std::string title()      { return take(sel_title(d_)); }
    std::string currentUrl() { return take(sel_current_url(d_)); }
    std::string pageSource() { return take(sel_page_source(d_)); }
    void back()    { check(sel_back(d_), "back"); }
    void forward() { check(sel_forward(d_), "forward"); }
    void refresh() { check(sel_refresh(d_), "refresh"); }

    // find
    WebElement findElement(const By &by) {
        sel_element *e = sel_find_element(d_, by.strategy.c_str(), by.value.c_str());
        if (!e) throw WebDriverError(17, "no such element: " + by.strategy + "=" + by.value);
        return WebElement(e);
    }

    // scripts — returns the value as JSON text.
    std::string executeScript(const std::string &script, const std::string &argsJson = "") {
        check(sel_execute_script(d_, script.c_str(), argsJson.empty() ? nullptr : argsJson.c_str()), "executeScript");
        return take(sel_last_value(d_));
    }

    // raw command; returns the value as JSON text.
    std::string execute(const std::string &command, const std::string &paramsJson = "") {
        check(sel_execute(d_, command.c_str(), paramsJson.empty() ? nullptr : paramsJson.c_str()), command.c_str());
        return take(sel_last_value(d_));
    }

    // TLS (call before a factory when constructing manually — see openHandle).
    sel_driver *raw() const { return d_; }
private:
    explicit WebDriver(sel_driver *d) : d_(d) {}
    void reset(sel_driver *d) { if (d_) { sel_execute(d_, "quit", "{}"); sel_close(d_); } d_ = d; }
    static const char *opt(const std::string &s) { return s.empty() ? nullptr : s.c_str(); }

    template <class F>
    static WebDriver make(const std::string &commandExecutor, F factory) {
        sel_driver *d = sel_open(commandExecutor.c_str());
        if (!d) throw WebDriverError(-1, "failed to open session handle");
        int rc = factory(d);
        if (rc != 0) {
            std::string msg = take(sel_last_error(d));
            int code = sel_last_error_code(d);
            sel_close(d);
            throw WebDriverError(rc == -1 && code == 0 ? -1 : code,
                                 msg.empty() ? "session creation failed" : msg);
        }
        return WebDriver(d);
    }
    void check(int rc, const char *what) {
        if (rc != 0) {
            std::string msg = take(sel_last_error(d_));
            int code = sel_last_error_code(d_);
            throw WebDriverError(rc == -1 && code == 0 ? -1 : code,
                                 msg.empty() ? (std::string(what) + " failed") : msg);
        }
    }
    sel_driver *d_;
};

// ---- pure engine helpers ----
inline std::string route(const std::string &command) { return take(sel_route(command.c_str())); }
inline int errorCode(const std::string &w3cError) { return sel_error_code(w3cError.c_str()); }
inline std::string locator(const std::string &strategy, const std::string &value) {
    return take(sel_locator(strategy.c_str(), value.c_str()));
}
inline std::string resolveDriver(const std::string &browser, const std::string &hint = "") {
    return take(sel_resolve_driver(browser.c_str(), hint.empty() ? nullptr : hint.c_str()));
}

} // namespace selenium

#endif // SELENIUM_HPP
