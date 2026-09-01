defmodule SeleniumTest do
  @moduledoc """
  Elixir tests over the shared Selenium NIF (the SAME compiled :selenium_nif the
  Erlang binding owns, on the code path via ERL_LIBS / SELENIUM_NIF_EBIN). FFI
  checks run with no browser; the live check needs chromedriver and skips when
  absent.

  NOTE: authored on a box without Elixir; verified on catchyos (Elixir +
  Erlang/BEAM). The Erlang NIF underneath is fully live-verified.
  """
  use ExUnit.Case

  test "route" do
    assert Selenium.route("get") == "POST /session/:sessionId/url"
    assert Selenium.route("nope") == ""
  end

  test "error_code" do
    assert Selenium.error_code("no such element") == 17
    assert Selenium.error_code("") == 0
  end

  test "locator id rewrite" do
    assert Selenium.locator("id", "main") =~ ~s(*[id=)
  end

  test "transport failure" do
    assert {:error, {-1, _}} = Selenium.chrome("http://127.0.0.1:1")
  end

  @tag :live
  test "live chrome + surface" do
    case System.find_executable("chromedriver") do
      nil ->
        # chromedriver absent — skip
        :ok

      driver_bin ->
        {web_port, web} = start_content_server()
        base = "http://127.0.0.1:#{web_port}"
        cd_port = free_port()
        cd = Port.open({:spawn_executable, driver_bin}, [:binary, args: ["--port=#{cd_port}"]])

        try do
          assert wait_up(cd_port, 10_000)
          {:ok, d} = Selenium.headless_chrome("http://127.0.0.1:#{cd_port}")

          try do
            assert byte_size(Selenium.session_id(d)) > 0

            {:ok, _} = Selenium.get(d, base <> "/one")
            assert {:ok, "Page One"} = Selenium.title(d)
            # one-arg find via the By factory (Selenium-style)
            {:ok, hdr} = Selenium.find_element(d, Selenium.By.id("hdr"))
            assert {:ok, "One"} = Selenium.element_text(d, hdr)

            # navigation — one-arg find via a literal locator tuple
            {:ok, go} = Selenium.find_element(d, {:id, "go"})
            {:ok, _} = Selenium.click(d, go)
            assert {:ok, "Page Two"} = Selenium.title(d)
            {:ok, _} = Selenium.back(d)
            assert {:ok, "Page One"} = Selenium.title(d)

            # cookies
            {:ok, _} = Selenium.delete_all_cookies(d)
            {:ok, _} = Selenium.add_cookie(d, %{"name" => "flavor", "value" => "mint"})
            {:ok, c} = Selenium.cookie(d, "flavor")
            assert Map.get(c, "value") == "mint"

            # windows
            {:ok, handles} = Selenium.window_handles(d)
            assert length(handles) >= 1
            {:ok, _} = Selenium.set_window_rect(d, %{"width" => 900, "height" => 650})
            {:ok, rect} = Selenium.get_window_rect(d)
            assert Map.get(rect, "width") == 900

            # script shapes
            assert {:ok, 42} = Selenium.execute_script(d, "return 6*7;")
            assert {:ok, "hi"} = Selenium.execute_script(d, "return 'hi';")
            assert {:ok, 42} = Selenium.execute_script(d, "return arguments[0]+arguments[1];", [40, 2])

            # W3C actions
            {:ok, btn} = Selenium.find_element(d, "id", "btn")
            {:ok, br} = Selenium.element_rect(d, btn)
            cx = trunc(Map.get(br, "x") + Map.get(br, "width") / 2)
            cy = trunc(Map.get(br, "y") + Map.get(br, "height") / 2)

            {:ok, _} =
              Selenium.perform_actions(d, [
                %{
                  "type" => "pointer",
                  "id" => "mouse",
                  "parameters" => %{"pointerType" => "mouse"},
                  "actions" => [
                    %{"type" => "pointerMove", "duration" => 0, "x" => cx, "y" => cy},
                    %{"type" => "pointerDown", "button" => 0},
                    %{"type" => "pointerUp", "button" => 0}
                  ]
                }
              ])

            {:ok, hdr2} = Selenium.find_element(d, "id", "hdr")
            assert {:ok, "clicked"} = Selenium.element_text(d, hdr2)
            {:ok, _} = Selenium.clear_actions(d)

            # screenshot
            {:ok, shot} = Selenium.screenshot(d)
            raw = Base.decode64!(shot)
            assert binary_part(raw, 1, 3) == "PNG"

            # negative path
            assert {:error, {17, _}} = Selenium.find_element(d, "id", "does-not-exist")
          after
            Selenium.quit(d)
          end
        after
          Port.close(cd)
          send(web, :stop)
        end
    end
  end

  # ---- helpers ----

  defp free_port do
    {:ok, s} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(s)
    :gen_tcp.close(s)
    port
  end

  defp wait_up(_port, t) when t <= 0, do: false

  defp wait_up(port, t) do
    case :gen_tcp.connect({127, 0, 0, 1}, port, [], 500) do
      {:ok, s} ->
        :gen_tcp.close(s)
        true

      _ ->
        Process.sleep(100)
        wait_up(port, t - 100)
    end
  end

  @page_one "<!doctype html><title>Page One</title><h1 id=\"hdr\">One</h1>" <>
              "<a id=\"go\" href=\"/two\">to two</a>" <>
              "<button id=\"btn\" onclick=\"document.getElementById('hdr').textContent='clicked'\">b</button>"
  @page_two "<!doctype html><title>Page Two</title><h1 id=\"hdr\">Two</h1>"

  defp start_content_server do
    {:ok, l} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(l)
    pid = spawn(fn -> accept_loop(l) end)
    {port, pid}
  end

  defp accept_loop(l) do
    case :gen_tcp.accept(l, 200) do
      {:ok, sock} ->
        spawn(fn -> serve(sock) end)
        accept_loop(l)

      {:error, :timeout} ->
        receive do
          :stop -> :gen_tcp.close(l)
        after
          0 -> accept_loop(l)
        end

      {:error, _} ->
        :ok
    end
  end

  defp serve(sock) do
    case :gen_tcp.recv(sock, 0, 2000) do
      {:ok, req} ->
        body =
          case :binary.match(req, "/two") do
            :nomatch -> @page_one
            _ -> @page_two
          end

        resp = [
          "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: ",
          Integer.to_string(byte_size(body)),
          "\r\nConnection: close\r\n\r\n",
          body
        ]

        :gen_tcp.send(sock, resp)

      _ ->
        :ok
    end

    :gen_tcp.close(sock)
  end
end
