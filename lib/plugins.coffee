# support server-side plugins

fs = require 'fs'
path = require 'path'
glob = require 'glob'

module.exports = exports = (argv) ->

# NOTE: plugins are now in their own package directories alongside this one...
# Plugins are in directories of the form wiki-package-*
# those with a server component will have a server directory

	plugins = {}

	# http://stackoverflow.com/questions/10914751/loading-node-js-modules-dynamically-based-on-route

	startServer = (params, plugin) ->
		server = "#{argv.packageDir}/#{plugin}/server/server.js"
		fs.exists server, (exists) ->
			if exists
				console.log 'starting plugin', plugin
				try
					plugins[plugin] = require server
					plugins[plugin].startServer?(params)
				catch e
					console.log 'failed to start plugin', plugin, e?.stack or e

	startServers = (params) ->
		glob "wiki-plugin-*", {cwd: argv.packageDir}, (e, plugins) ->
			startServer params, plugin for plugin in plugins


	{startServers}