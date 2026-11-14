# Post the entity server's protobuf span records to an OTLP/HTTP collector, as AppSignal's collector wants them.
#   APPSIGNAL_PUSH_API_KEY=... OTEL_COLLECTOR_URL=https://<id>.<region>.appsignal-collector.net \
#   APPSIGNAL_APP_NAME=fabric-entity-server APPSIGNAL_APP_ENV=dev elixir tools/otlp_post_pb.exs <records.pb> [--dry]
# Each record in the file is a 4-byte little-endian length and one ScopeSpans message. The resource, which holds the
# key, is built here from the environment and never written to the file.
defmodule OtlpPostPb do
  import Bitwise

  def main([file | rest]) do
    env = fn k -> System.get_env(k) || fail("set #{k}") end
    key = env.("APPSIGNAL_PUSH_API_KEY")
    base = env.("OTEL_COLLECTOR_URL")
    {:ok, host} = :inet.gethostname()

    attrs = [
      {"appsignal.config.push_api_key", key},
      {"appsignal.config.name", env.("APPSIGNAL_APP_NAME")},
      {"appsignal.config.environment", env.("APPSIGNAL_APP_ENV")},
      {"appsignal.config.revision", System.get_env("APPSIGNAL_REVISION") || "dev"},
      {"appsignal.config.language_integration", "c"},
      {"service.name", System.get_env("OTEL_SERVICE_NAME") || "entity-server"},
      {"host.name", List.to_string(host)}
    ]

    records = records(File.read!(file), [])
    body = request(attrs, records)
    if "--dry" in rest, do: IO.puts("RESULT: PASS dry #{length(records)} records #{byte_size(body)} bytes"), else: post(base, body, length(records))
  end

  def main(_), do: fail("usage: otlp_post_pb.exs <records.pb> [--dry]")

  def request(attrs, records) do
    # Resource: attributes 1, dropped_attributes_count 2; ResourceSpans: resource 1, scope_spans 2, schema_url 3.
    resource = Enum.map_join(attrs, fn {k, v} -> field(1, key_value(k, v)) end) <> <<0x10, 0>>
    scopes = Enum.map_join(records, fn r -> field(2, r) end)
    field(1, field(1, resource) <> scopes <> field(3, "https://opentelemetry.io/schemas/1.27.0"))
  end

  def records(<<>>, acc), do: Enum.reverse(acc)
  def records(<<n::little-32, r::binary-size(n), rest::binary>>, acc), do: records(rest, [r | acc])
  def records(_, _), do: fail("the record file is cut short")

  defp key_value(k, v), do: field(1, k) <> field(2, field(1, v))
  defp field(n, bin), do: <<(n <<< 3) ||| 2>> <> varint(byte_size(bin)) <> bin
  defp varint(v) when v < 128, do: <<v>>
  defp varint(v), do: <<(v &&& 127) ||| 128>> <> varint(v >>> 7)

  defp post(base, body, n) do
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)
    url = String.to_charlist(String.trim_trailing(base, "/") <> "/v1/traces")
    ssl = [ssl: [verify: :verify_peer, cacerts: :public_key.cacerts_get(), customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]]]

    case :httpc.request(:post, {url, [], ~c"application/x-protobuf", body}, ssl, []) do
      {:ok, {{_, code, _}, _, _}} when code in 200..299 -> IO.puts("RESULT: PASS #{code} #{n} records")
      {:ok, {{_, code, _}, _, resp}} -> IO.puts("RESULT: FAIL #{code} #{String.slice(to_string(resp), 0, 200)}"); System.halt(1)
      {:error, e} -> IO.puts("RESULT: ERROR #{inspect(e)}"); System.halt(2)
    end
  end

  defp fail(msg) do
    IO.puts("RESULT: ERROR " <> msg)
    System.halt(2)
  end
end

OtlpPostPb.main(System.argv())
