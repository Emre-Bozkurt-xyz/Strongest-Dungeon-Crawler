--!strict
-- Studio-only: makes unpublished clips playable in a playtest.
--
-- The Animation Editor saves KeyframeSequences under ServerStorage.RBX_ANIMSAVES, which clients
-- cannot see. Any save named after a declared clip that has no published ID yet (a full key such as
-- "sword_light_1h/slash_1") is copied into ReplicatedStorage.AnimationDrafts, where the client's
-- AssetLoader registers it under a temporary ID. Live servers never run this, so a draft can only
-- ever stand in during development.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local AnimationRegistry = require(ReplicatedStorage.Shared.Animation.AnimationRegistry)

local AnimationDrafts = {}

local FOLDER_NAME = "AnimationDrafts"

function AnimationDrafts.start()
	if not RunService:IsStudio() then
		return
	end
	local saves = ServerStorage:FindFirstChild("RBX_ANIMSAVES")
	if not saves then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME

	local mirrored: { string } = {}
	for _, save in saves:GetDescendants() do
		if save:IsA("KeyframeSequence") then
			local clip = AnimationRegistry.get(save.Name)
			if clip and not clip.id then
				if folder:FindFirstChild(save.Name) then
					warn(`[AnimationDrafts] more than one save named '{save.Name}'; using the first`)
				else
					save:Clone().Parent = folder
					table.insert(mirrored, save.Name)
				end
			end
		end
	end

	if #mirrored == 0 then
		folder:Destroy()
		return
	end
	folder.Parent = ReplicatedStorage
	table.sort(mirrored)
	print(`[AnimationDrafts] playing {#mirrored} unpublished draft(s): {table.concat(mirrored, ", ")}`)
end

return AnimationDrafts
