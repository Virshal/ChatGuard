-- metavirtual, 2021
-- Responsible for protecting the chat remote on the server.

--[[

	ChatGuard:TrustPlayer(player, trusted [default: true]) [yields]
	- Allows the selected player to send messages.
	- Useful if you want to require players to do certain actions before they can chat,
	- such as click a button or walk somewhere.

	ChatGuard:IsPlayerTrusted(player) [yields]
	- Check if a player is trusted. You may need TRUST_PLAYERS_BY_DEFAULT to false, depending on your use case.
	- Returns a boolean.

-]]

-- If this is set to false, then players will not be able to talk until ChatGuard:TrustPlayer is called.
local TRUST_PLAYERS_BY_DEFAULT = true

local Players = game:GetService("Players")
local Chat = game:GetService("Chat")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = script:WaitForChild("Modules")

local Signal = require(Modules.Signal)
local ChatService = require(game:GetService("ServerScriptService"):WaitForChild("ChatServiceRunner").ChatService)

local MESSAGE_CACHE_SIZE = 16

local ChatGuard = {ChatProfiles = {}, _running = false, _started = Signal.new()}

-- Simulate a message sending: game.ReplicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest:FireServer("test", "All")

function ChatGuard._onPlayerAdded(player)
	ChatGuard.ChatProfiles[player] = {
		messages = {};
		shadowBanned = false;
		untrusted = (not TRUST_PLAYERS_BY_DEFAULT);
		chatBind = Instance.new("BindableEvent");
		messageValidated = false
	}

	local function OnChatted(message)
		ChatGuard.ChatProfiles[player].messageValidated = true

		table.insert(ChatGuard.ChatProfiles[player].messages, message)

		if #ChatGuard.ChatProfiles[player].messages > MESSAGE_CACHE_SIZE then
			table.remove(ChatGuard.ChatProfiles[player].messages, 1)
		end
	end

	player.Chatted:Connect(OnChatted)
end

function ChatGuard._onSayMessageRequest(player, message, channel)
	if ChatGuard.ChatProfiles[player].shadowBanned then
		return
	end

	local messageFound = false

	for i = 1, 3 do
		for i, data in pairs (ChatGuard.ChatProfiles[player].messages) do
			local messageString = data

			if messageString == message then
				messageFound = true

				-- Remove message from cache
				ChatGuard.ChatProfiles[player].messages[i] = nil

				break
			end
		end

		if messageFound then
			break
		end

		RunService.Heartbeat:Wait()
	end

	if not messageFound then
		print("Chat shadow banned", player)

		ChatGuard.ChatProfiles[player].shadowBanned = true
		return
	end
end

function ChatGuard._onPlayerRemoving(player)
	-- Clear player from memory
	ChatGuard.ChatProfiles[player] = nil
end

function ChatGuard._messageSwallower(SpeakerName, Message, ChannelName)
	local ChatLocalization = nil
	pcall(function() ChatLocalization = require(game:GetService("Chat").ClientChatModules.ChatLocalization) end)
	if ChatLocalization == nil then ChatLocalization = {} end

	if not ChatLocalization.FormatMessageToSend or not ChatLocalization.LocalizeFormattedMessage then
		function ChatLocalization:FormatMessageToSend(key,default) return default end
	end

	local speaker = ChatService:GetSpeaker(SpeakerName)
	local channel = ChatService:GetChannel(ChannelName)
	local player = speaker:GetPlayer()

	if player and speaker and channel then
		if ChatGuard.ChatProfiles[player].shadowBanned or not (ChatGuard.ChatProfiles[player].messageValidated) then
			-- Send the message to themselves
			speaker:SendMessage(Message, ChannelName, SpeakerName, Message.ExtraData)

			-- Swallow the message; this means that no other players will see it.
			return true
		elseif ChatGuard.ChatProfiles[player].untrusted then
			-- Tell the user that they have to 'wait before speaking'
			local timeDiff = 30

			local msg = ChatLocalization:FormatMessageToSend("GameChat_ChatFloodDetector_MessageDisplaySeconds",
				string.format("You must wait %d %s before sending another message!", timeDiff, (timeDiff > 1) and "seconds" or "second"),
				"RBX_NUMBER",
				tostring(timeDiff)
			)

			speaker:SendSystemMessage(msg, ChannelName)

			-- Swallow the message
			return true
		else
			if ChatGuard.ChatProfiles[player].messageValidated then
				ChatGuard.ChatProfiles[player].messageValidated = false

				-- Send the message
				return false
			end
		end
	end

	-- Send the message
	return false
end

function ChatGuard:Start()
	Players.PlayerAdded:Connect(self._onPlayerAdded)
	Players.PlayerRemoving:Connect(self._onPlayerRemoving)

	table.foreach(Players:GetPlayers(), function(_, player)
		self._onPlayerAdded(player)
	end)

	ChatService:RegisterProcessCommandsFunction("chat_guard_swallow", self._messageSwallower)
	ReplicatedStorage:WaitForChild("DefaultChatSystemChatEvents"):WaitForChild("SayMessageRequest").OnServerEvent:Connect(self._onSayMessageRequest)
	
	self._running = true
end

function ChatGuard:_waitForStart()
	if not self._running then
		self._started:Wait()
	end
end

function ChatGuard:TrustPlayer(player, trusted)
	self:_waitForStart()
	
	local untrusted = false
	
	if trusted ~= nil then
		untrusted = (not trusted)
	end
	
	if self.ChatProfiles[player] then
		self.ChatProfiles[player].untrusted = untrusted
	end
end

function ChatGuard:IsPlayerTrusted(player)
	self:_waitForStart()
	
	return self.ChatProfiles[player] and (not self.ChatProfiles[player].untrusted)
end

return ChatGuard