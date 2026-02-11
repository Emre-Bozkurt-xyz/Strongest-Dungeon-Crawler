-- Main server initialization script
print("Server starting...")

local Bootstrap = require(script.Bootstrap)
Bootstrap.startAll()

print("Server initialized")
