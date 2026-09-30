class_name CurlCommand
extends BaseCommand
## A teaching HTTP client. Talks to the machine's networking model: resolves
## the host, connects to a port from net.hosts, and returns the canned response.


const STATUS_TEXT := {
	200: "OK", 201: "Created", 204: "No Content", 301: "Moved Permanently",
	302: "Found", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden",
	404: "Not Found", 500: "Internal Server Error", 502: "Bad Gateway",
	503: "Service Unavailable",
}


func get_command_name() -> String: return "curl"
func get_category() -> String: return "network"
func get_summary() -> String: return "make an HTTP request to a URL"
func get_usage() -> String: return "curl [-I] [-s] URL"
func get_manual() -> String:
	return """`curl` fetches a URL over HTTP and prints the response body.
  curl http://status.internal/health   fetch and print the page
  curl -I http://host/                  headers only (great for checking status)
  curl -s http://host/ > out.txt        quiet; save the body to a file
Errors tell you where it broke: '(6) Could not resolve host' is DNS,
'(7) Connection refused' means nothing is listening on that port."""


func execute(ctx: CommandContext) -> int:
	var parsed := parse_options(ctx.args(), "H", ["header"])
	var head_only: bool = parsed.flags.has("I") or parsed.flags.has("head")
	if parsed.operands.is_empty():
		ctx.err("curl: try 'curl --help' for more information\n")
		return 2
	var url := str(parsed.operands[0])

	var scheme_port := 443 if url.begins_with("https://") else 80
	url = url.trim_prefix("https://").trim_prefix("http://")
	var slash := url.find("/")
	var authority := url if slash == -1 else url.substr(0, slash)
	var path := "/" if slash == -1 else url.substr(slash)
	var host := authority
	var port := scheme_port
	var colon := authority.find(":")
	if colon != -1:
		host = authority.substr(0, colon)
		port = int(authority.substr(colon + 1))

	var m := ctx.machine()
	var ip := m.resolve_host(host)
	if ip == "":
		ctx.err("curl: (6) Could not resolve host: %s\n" % host)
		return 6
	var peer := m.host_at(ip)
	if peer.is_empty() and not ip.begins_with("127."):
		ctx.err("curl: (7) Failed to connect to %s port %d: No route to host\n" % [host, port])
		return 7
	var ports: Dictionary = peer.get("ports", {})
	var resp: Dictionary = ports.get(str(port), {})
	if resp.is_empty():
		ctx.err("curl: (7) Failed to connect to %s port %d: Connection refused\n" % [host, port])
		return 7
	if str(resp.get("proto", "http")) not in ["http", "https"]:
		ctx.err("curl: (52) Empty reply from server\n")
		return 52

	# curl (without -f) succeeds whenever it got a reply, whatever the HTTP status.
	var status := int(resp.get("status", 200))
	if head_only:
		ctx.out("HTTP/1.1 %d %s\n" % [status, STATUS_TEXT.get(status, "")], "" if status < 400 else "warn")
		for k in resp.get("headers", {}):
			ctx.out("%s: %s\n" % [k, resp.headers[k]])
		ctx.out("\n")
		return 0
	var body := str(resp.get("body", ""))
	ctx.out(body if body == "" or body.ends_with("\n") else body + "\n")
	return 0
