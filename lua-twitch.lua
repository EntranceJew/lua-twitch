local socket = require("socket")

--[[
	@TODO:
	* make a subscriber thing 
]]

local TwitchBot = {
	DEFAULT_HOST = 'irc.chat.twitch.tv',
	DEFAULT_PORT = 6667,
	SECURE_PORT = 443,
	COMMAND_RATE = 20/30, -- we're allowed to send 20 times every 30 seconds, or once every 20/30 second
	commands = {},
	handlers = {}
}

TwitchBot.__index = TwitchBot
setmetatable(TwitchBot, {
	__call = function (class, ...)
		return class.new(...)
	end,
})

---
-- Create a new TwitchBot.
-- @name TwitchBot.new
-- @param ... Whatever
-- @return A new instance of TwitchBot
function TwitchBot.new(nickname, password, channel, host, port)
	local self = setmetatable({}, TwitchBot)
	
	-- set properties on self here
	assert(nickname and type(nickname) == 'string', "nickname must be set and a string")
	self.nickname = string.lower(nickname) 
	assert(password and type(password) == 'string' and password ~= "", "password must be set and a non-empty string")
	self.password = password
	assert(channel and type(channel) == 'string', "channel must be set and a string")
	self.channel = string.lower(channel)
	
	self.waitTime = 0
	self.queue = {}
	self.messages = {}
	self.connected = false
	self.host = host or TwitchBot.DEFAULT_HOST
	self.port = port or TwitchBot.DEFAULT_PORT
	
	self.debug = true
	
	self:connect()
	
	return self
end

function TwitchBot:connect()
	local conerr
	
	if self.connection == nil then
		if self.port == TwitchBot.SECURE_PORT then
			-- be secure
			assert(false, "ssl not implemented")
		else
			self.connection, conerr = socket.tcp()
		end
		assert(self.connection ~= nil, "socket failed: " .. tostring(conerr))
		
		self.connection:settimeout(0)
	end
	self.connection:connect(self.host, self.port)
end

function TwitchBot:disconnect()
	if self.connection ~= nil then
		self.connection:close()
	end
	self.connection = nil
end

---
-- Update the command queue and send any messages that weren't released yet.
function TwitchBot:update(dt)
	self:read()
	
	if self.waitTime > 0 then
		self.waitTime = self.waitTime - dt
		if self.waitTime < 0 then
			self.waitTime = 0
		end
	end
	
	if self.waitTime <= 0 and #self.queue > 0 then
		if self.connection ~= nil then
			local snd = self.queue[1]
			if self.debug then
				print('dump[OUT]', snd)
			end
			local sent, senderr, lastbytesent = self.connection:send(snd..'\r\n')
			if sent ~= nil then
				table.remove(self.queue, 1)
				self.waitTime = TwitchBot.COMMAND_RATE
				return true
			end
			assert(sent ~= nil, "Send failed:" .. tostring(senderr) .. "; last byte sent:" .. tostring(lastbytesent))
			return false
		end
	end
end

function TwitchBot:send(data)
	table.insert(self.queue, data)
	return false
end

function TwitchBot:sendMessage(message)
	self:send("PRIVMSG " .. self.channel .. " :" .. message)
end

function TwitchBot.commands.login(self)
	if not self.connected then
		self:connect()
		socket.sleep(1)
		assert(self.password and type(self.password) == 'string' and self.password ~= "", "password must be set and a non-empty string")
		self:send("PASS "..self.password)
		self:send("NICK "..self.nickname)
		--self:send("CAP REQ :twitch.tv/membership")
		--self:send("CAP REQ :twitch.tv/tags")
		self.connected = true
	end
end

TwitchBot.handlers["376"] = function(self, rawcmd, tags, prefix, cmd, param)
	self:send("JOIN "..self.channel)
end

TwitchBot.handlers["PRIVMSG"] = function(self, rawcmd, tags, prefix, cmd, param)
	if param ~= nil then
		param = string.sub(param,2)
		local param1, param2 = string.match(param,"^([^:]+) :(.*)$")
		local username, userhost = string.match(prefix,"^([^!]+)!(.*)$")
		table.insert(self.messages, {
			username = username,
			message = param2,
			tags = tags,
		})
	end
end

function TwitchBot:read()
	local buffer, err
	local tags, prefix, cmd, param
	err = nil
	if self.connection ~= nil then
		buffer, err = self.connection:receive("*l")
		if err ~= nil or err == "timeout" then
			TwitchBot.commands.login(self)
		end
		if buffer ~= nil then
			if self.debug then
				print('dump[IN]', buffer, err)
			end
			if string.sub(buffer,1,4) == "PING" then
				self:send(string.gsub(buffer,"PING","PONG",1))
			else
				tags, prefix, cmd, param = string.match(buffer, "^([^:]*:?)([^ ]+) ([^ ]+)(.*)$")
				if TwitchBot.handlers[cmd] and type(TwitchBot.handlers[cmd]) == "function" then
					TwitchBot.handlers[cmd](self, buffer, tags, prefix, cmd, param)
				end
			end
		end
	else
		assert(false, "No connection.")
	end
	return buffer, err
end

function TwitchBot:readMessage()
	if #self.messages <= 0 then 
		return nil
	end
	return table.remove(self.messages, 1)
end

return TwitchBot