# Put the shared selenium_nif OTP app (built by the Erlang binding) on the code
# path. mix does NOT fold ERL_LIBS in, so the .tests.ae harness passes the NIF
# ebin dir as SELENIUM_NIF_EBIN and we append it here — the NIF's
# code:priv_dir(selenium_nif) then finds priv/selenium_nif.so the OTP way.
case System.get_env("SELENIUM_NIF_EBIN") do
  nil -> :ok
  ebin -> Code.append_path(ebin)
end

ExUnit.start()
