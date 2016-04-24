local luatwitch = require('lua-twitch')
local myBot
io.stdout:setvbuf("no")

function love.load(arg)
	myBot = luatwitch.new('your_username', 'oauth:your_oauth_key', '#channel_to_join')
end

local msg
function love.update(dt)
	myBot:update(dt)
	local msg = myBot:message()
	if msg ~= nil then
		print('<CHAT>', msg.nick, 'said: ', msg.message)
	end
end

function love.keypressed(key, scancode)
	if key == "k" then
		myBot:sendMessage("[botmsg] oh boy i love watching %(VIDEOGAME)")
	end
end