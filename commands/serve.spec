# =============================================================================
#  commands/serve.spec — 'urb serve' (Command Engine)
#  DATOS: se leen y validan; nunca se ejecutan.
# =============================================================================
name=serve
summary=Serve the current directory over HTTP with Python's standard http.server
usage=urb serve [--port <port>] [--bind <ip>] [--dir <directory>] [--yes]
requires=python3
option=port|port|8000|SERVE_PORT|TCP port to listen on (1024-65535 without root)
option=bind|ip|127.0.0.1|SERVE_BIND|Listen address. Local by default; any other address exposes the files to the network
option=dir|dir|.||Directory to share (default: the current directory)
option=yes|flag|||Confirm a non-local listen address without asking (explicit authorization)
note=Stop it with Ctrl+C. URB never opens firewall ports, needs no root and installs nothing.
note=Everything inside the directory (and its subdirectories) can be downloaded by whoever reaches the address.
example=urb serve
example=urb serve --port 8080
example=urb serve --port 8080 --bind 127.0.0.1
example=urb serve --dir ~/urb-labs/demo/exploits --port 9000
example=urb serve --bind 0.0.0.0 --port 8080 --yes        (exposed to your network: asks unless --yes)
