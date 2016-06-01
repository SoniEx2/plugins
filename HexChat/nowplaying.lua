local lgi = require('lgi')
local GLib = lgi.require('GLib')
local Gio = lgi.require('Gio')

hexchat.register('NowPlaying', '2', 'Announce songs from MPRIS2 clients')

local bus
local cancellable = Gio.Cancellable()

Gio.bus_get(Gio.BusType.SESSION, cancellable, function (object, result)
	local connection, err = Gio.bus_get_finish(result)

	if err then
		local front_ctx = hexchat.find_context(nil, nil)
		front_ctx:print('NP: Error connecting to dbus: ' .. tostring(err))
	else
		bus = connection
	end
end)

local function get_players (callback)
	bus:call('org.freedesktop.DBus', -- bus
		'/org/freedesktop/DBus', -- object
		'org.freedesktop.DBus', -- interface
		'ListNames', -- method
		nil, -- params
		GLib.VariantType('(as)'), -- return type
		Gio.DBusCallFlags.NONE, -1,
		cancellable,
		function (connection, result)
			local ret, err = connection:call_finish(result)

			if err then
				-- print('NP: Error ' .. tostring(err))
				return
			elseif #ret ~= 1 then
				return
			end

			local players = {}
			local array = ret.value[1]
			for i = 1, #array do
				local player_name = array[i]:match('^org%.mpris%.MediaPlayer2%.([^.]+)$')
				if player_name then
					players[#players + 1] = player_name
				end
			end

			if #players == 0 then
				callback(nil)
			else
				callback(players)
			end
		end)
end

local function print_nowplaying (player)
	local original_context = hexchat.props.context

	bus:call('org.mpris.MediaPlayer2.' .. player,
		'/org/mpris/MediaPlayer2',
		'org.freedesktop.DBus.Properties',
		'Get',
		GLib.Variant('(ss)', {'org.mpris.MediaPlayer2.Player', 'Metadata'}),
		GLib.VariantType('(v)'),
		Gio.DBusCallFlags.NONE, -1,
		cancellable,
		function (connection, result)
			local ret, err = connection:call_finish(result)

			if err then
				-- print('NP: Error ' .. tostring(err))
				return
			elseif #ret ~= 1 then
				return
			end

			local metadata = ret[1].value -- a{sv}
			local title = metadata['xesam:title'] or 'Unknown Title'
			local album = metadata['xesam:album'] or 'Unknown Album'
			local artist
			if metadata['xesam:artist'] then
				artist = metadata['xesam:artist'][1]
			else
				artist = 'Unknown Artist'
			end

			if not original_context:set() then
				return
			end

			-- TODO: Support customizing the command
			hexchat.command(string.format('me is now playing %s by %s on %s.', title, artist, album))
		end)
end

hexchat.hook_command('np', function (word, word_eol)
	if not bus then
		print('NP: Connection to dbus not yet established')
		return hexchat.EAT_ALL
	end

	local original_context = hexchat.props.context
	get_players (function (players)
		if not original_context:set() then
			return -- If the tab was closed just don't care
		end

		if not players then
			print('NP: No player found running.')
		elseif #word > 1 then
			local player = word[2]:lower()

			for _, name in pairs(players) do
				if player == name:lower() then
					print_nowplaying(name)
					return
				end
			end

			print('NP: Player ' .. word[2] .. ' not found.')
		elseif #players == 1 then
			print_nowplaying(players[1])
		else
			print('NP: You have multiple players running, please specify a name:\n\t' .. tostring(players))
		end
	end)

	return hexchat.EAT_ALL
end, 'NP [player]')

hexchat.hook_unload (function ()
	-- FIXME: Seems this can possibly crash
	-- /np
	-- /lua unload ~/.config/hexchat/addons/nowplaying.lua
	cancellable:cancel()
end)
