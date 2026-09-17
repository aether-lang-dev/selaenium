# surface_test.jl — no-browser, no-engine ABI-surface guard for the Julia binding.
#
# Asserts (by reflection) that every public method of the full-feature surface
# EXISTS with a callable signature — the compile-time reference the crystal/swift
# surface specs provide, done here with `hasmethod` (Julia has no separate compile
# step). A rename or accidental removal of any listed method fails this test.
# Pure reflection + the By/Keys value facts: it never opens a session and does not
# need the engine .so, so it always runs (unlike ffi_test, which needs the .so).
using Test
include("../src/Selenium.jl")
using .Selenium

# Shorthand: a public function `f` must have a method accepting argument types
# `ts` (a Tuple type). `hasmethod` is pure reflection — no call is made.
has(f, ts) = @test hasmethod(f, ts)

@testset "Julia ABI surface — public method table" begin
    D = Selenium.WebDriver
    E = Selenium.WebElement
    S = Selenium.ShadowRoot
    L = Selenium.Locator
    Sel = Selenium.Select
    Act = Selenium.Actions
    W = Selenium.Wait
    B = Selenium.BiDi
    DP = Selenium.DriverProcess

    @testset "engine helpers" begin
        has(route, Tuple{AbstractString})
        has(errorcode, Tuple{AbstractString})
        has(locator, Tuple{AbstractString,AbstractString})
        has(execute, Tuple{D,AbstractString})
    end

    @testset "session lifecycle / driver mgmt" begin
        has(chrome, Tuple{AbstractString})
        has(chrome_tls, Tuple{AbstractString,AbstractDict,Selenium.TlsConfig})
        has(headless_chrome, Tuple{AbstractString})
        has(firefox, Tuple{AbstractString})
        has(headless_firefox, Tuple{AbstractString})
        has(edge, Tuple{AbstractString})
        has(headless_edge, Tuple{AbstractString})
        has(safari, Tuple{AbstractString})
        has(local_chrome, Tuple{})
        has(quit, Tuple{D})
        has(sessionid, Tuple{D})
        has(resolve_driver, Tuple{AbstractString})
        has(launch_driver, Tuple{AbstractString,Integer})
        has(ensure_driver, Tuple{AbstractString,AbstractString,Integer})
        has(driver_url, Tuple{DP})
        has(driver_pid, Tuple{DP})
        has(stop_driver, Tuple{DP})
    end

    @testset "navigation" begin
        has(get_url, Tuple{D,AbstractString})
        has(current_url, Tuple{D})
        has(title, Tuple{D})
        has(page_source, Tuple{D})
        has(back, Tuple{D})
        has(forward, Tuple{D})
        has(refresh, Tuple{D})
    end

    @testset "elements + finds" begin
        has(findelement, Tuple{D,L})
        has(find_element, Tuple{D,L})
        has(find_elements, Tuple{D,L})
        has(find_element, Tuple{E,L})      # element-scoped child find
        has(find_element, Tuple{S,L})      # shadow-scoped find
        has(active_element, Tuple{D})
        has(exists, Tuple{D,L})
        has(find_relative, Tuple{D,AbstractString,AbstractVector})
        has(find_relative_count, Tuple{D,AbstractString,AbstractVector})
        has(shadow_root, Tuple{E})
    end

    @testset "element ops" begin
        has(click, Tuple{E})
        has(clear, Tuple{E})
        has(send_keys, Tuple{E,AbstractString})
        has(text, Tuple{E})
        has(tag_name, Tuple{E})
        has(is_displayed, Tuple{E})
        has(is_enabled, Tuple{E})
        has(is_selected, Tuple{E})
        has(get_attribute, Tuple{E,AbstractString})
        has(get_dom_attribute, Tuple{E,AbstractString})
        has(get_property, Tuple{E,AbstractString})
        has(rect, Tuple{E})
        has(css_value, Tuple{E,AbstractString})
        has(value_of_css_property, Tuple{E,AbstractString})
        has(element_screenshot_base64, Tuple{E})
        has(submit, Tuple{E})
    end

    @testset "script / windows / frames" begin
        has(execute_script, Tuple{D,AbstractString})
        has(execute_async_script, Tuple{D,AbstractString})
        has(window_handles, Tuple{D})
        has(current_window_handle, Tuple{D})
        has(switch_to_window, Tuple{D,AbstractString})
        has(set_window_rect, Tuple{D,AbstractDict})
        has(get_window_rect, Tuple{D})
        has(maximize_window, Tuple{D})
        has(minimize_window, Tuple{D})
        has(fullscreen_window, Tuple{D})
        has(new_window, Tuple{D})
        has(close_window, Tuple{D})
        has(switch_to_frame, Tuple{D,Integer})
        has(switch_to_frame, Tuple{D,E})
        has(switch_to_parent_frame, Tuple{D})
        has(switch_to_default_content, Tuple{D})
    end

    @testset "alerts / cookies" begin
        has(accept_alert, Tuple{D})
        has(dismiss_alert, Tuple{D})
        has(alert_text, Tuple{D})
        has(send_alert_text, Tuple{D,AbstractString})
        has(alert_present, Tuple{D})
        has(add_cookie, Tuple{D,AbstractDict})
        has(get_cookies, Tuple{D})
        has(get_cookie, Tuple{D,AbstractString})
        has(delete_cookie, Tuple{D,AbstractString})
        has(delete_all_cookies, Tuple{D})
    end

    @testset "actions / timeouts / shots" begin
        has(perform_actions, Tuple{D,AbstractVector})
        has(clear_actions, Tuple{D})
        has(set_timeouts, Tuple{D,AbstractDict})
        has(set_page_load_timeout, Tuple{D,Integer})
        has(set_script_timeout, Tuple{D,Integer})
        has(implicitly_wait, Tuple{D,Integer})
        has(screenshot_base64, Tuple{D})
        has(print_pdf, Tuple{D})
        # fluent Actions builder verbs
        has(move_to_element, Tuple{Act,E})
        has(click, Tuple{Act})
        has(context_click, Tuple{Act})
        has(double_click, Tuple{Act})
        has(click_and_hold, Tuple{Act})
        has(release, Tuple{Act})
        has(drag_and_drop, Tuple{Act,E,E})
        has(key_down, Tuple{Act,AbstractString})
        has(key_up, Tuple{Act,AbstractString})
        has(send_keys, Tuple{Act,AbstractString})
        has(pause, Tuple{Act,Integer})
        has(build, Tuple{Act})
        has(perform, Tuple{Act})
    end

    @testset "Select" begin
        has(options, Tuple{Sel})
        has(all_selected_options, Tuple{Sel})
        has(first_selected_option, Tuple{Sel})
        has(select_by_index, Tuple{Sel,Integer})
        has(select_by_value, Tuple{Sel,AbstractString})
        has(select_by_visible_text, Tuple{Sel,AbstractString})
        has(deselect_all, Tuple{Sel})
        has(is_multiple, Tuple{Sel})
    end

    @testset "waits" begin
        has(wait, Tuple{D,Real})
        has(until, Tuple{W,Any})
        has(until_not, Tuple{W,Any})
        has(poll_every, Tuple{W,Real})
        has(wait_for_element, Tuple{D,L,Real})
        has(wait_for_visible, Tuple{D,L,Real})
        has(wait_for_clickable, Tuple{D,L,Real})
        has(wait_until_gone, Tuple{D,L,Real})
        has(wait_for_title_is, Tuple{D,AbstractString,Real})
        has(wait_for_title_contains, Tuple{D,AbstractString,Real})
        has(wait_for_url_is, Tuple{D,AbstractString,Real})
        has(wait_for_url_contains, Tuple{D,AbstractString,Real})
    end

    @testset "WebDriver-BiDi" begin
        has(bidi, Tuple{D})
        has(bidi_available, Tuple{D})
        has(subscribe, Tuple{B,AbstractVector})
        has(unsubscribe, Tuple{B,AbstractVector})
        has(next_event, Tuple{B,AbstractString,Integer})
        has(command, Tuple{B,AbstractString,AbstractDict,Integer})
        has(get_tree, Tuple{B,Integer})
        has(top_context, Tuple{B,Integer})
        has(evaluate, Tuple{B,AbstractString,Integer})
        has(evaluate_value, Tuple{B,AbstractString,Integer})
        has(navigate, Tuple{B,AbstractString,Integer})
        has(add_intercept, Tuple{B,AbstractString,AbstractString,Integer})
        has(remove_intercept, Tuple{B,AbstractString,Integer})
        has(continue_request, Tuple{B,AbstractString,Integer})
        has(fail_request, Tuple{B,AbstractString,Integer})
        has(provide_response, Tuple{B,AbstractString,Integer,AbstractString,AbstractString,Integer})
        has(continue_with_auth, Tuple{B,AbstractString,AbstractString,AbstractString,Integer})
        has(set_cache_behavior, Tuple{B,AbstractString,Integer})
        has(event_request_id, Tuple{AbstractString})
        has(lost_events, Tuple{B})
    end
end

@testset "By factory + Keys facts (values, no engine)" begin
    @test By.id("hdr").strategy == "id"
    @test By.class_name("b").strategy == "class name"
    @test By.css_selector("a.b").strategy == "css selector"
    @test By.xpath("//a").strategy == "xpath"
    @test codepoint(only(Keys.NULL)) == 0xE000
    @test codepoint(only(Keys.META)) == 0xE03D
    @test Keys.COMMAND == Keys.META
    @test endswith(Keys.chord(Keys.CONTROL, "a"), Keys.NULL)
end

println("PASS: Julia ABI-surface guard green")
