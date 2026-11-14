# Post one OTLP/JSON body the guest drained to a collector.
#   OTEL_EXPORTER_OTLP_ENDPOINT=<base> OTEL_EXPORTER_OTLP_HEADERS="k=v,k2=v2" elixir tools/otlp_post.exs traces|metrics|logs <body.json>
defmodule OtlpPost do
  def main([signal, file]) when signal in ~w(traces metrics logs) do
    base = System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") || fail("set OTEL_EXPORTER_OTLP_ENDPOINT")
    headers =
      for pair <- String.split(System.get_env("OTEL_EXPORTER_OTLP_HEADERS") || "", ",", trim: true),
          [k, v] = String.split(pair, "=", parts: 2),
          do: {String.to_charlist(String.trim(k)), String.to_charlist(String.trim(v))}

    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)
    url = String.trim_trailing(base, "/") <> "/v1/" <> signal
    body = File.read!(file)
    req = {String.to_charlist(url), headers, ~c"application/json", body}
    ssl = [ssl: [verify: :verify_peer, cacerts: :public_key.cacerts_get(), customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]]]

    case :httpc.request(:post, req, ssl, []) do
      {:ok, {{_, code, _}, _, _}} when code in 200..299 -> IO.puts("RESULT: PASS #{code}")
      {:ok, {{_, code, _}, _, _}} -> IO.puts("RESULT: FAIL #{code}"); System.halt(1)
      {:error, e} -> IO.puts("RESULT: ERROR #{inspect(e)}"); System.halt(2)
    end
  end

  def main(_), do: fail("usage: otlp_post.exs traces|metrics|logs <body.json>")

  defp fail(msg) do
    IO.puts("RESULT: ERROR " <> msg)
    System.halt(2)
  end
end

OtlpPost.main(System.argv())
