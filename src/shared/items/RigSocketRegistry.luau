--!strict
-- Shared rig socket contracts for equipment visual profiles.

local ItemTypes = require(script.Parent.ItemTypes)

local RigSocketRegistry = {}

local profiles: { [string]: ItemTypes.RigSocketProfile } = {
	R6 = {
		id = "R6",
		sockets = {
			Weapon_Main = {
				name = "Weapon_Main",
				recommendedParents = { "RightHand", "Right Arm" },
				legacyAliases = { "RightHand" },
				description = "Primary hand grip for main-hand weapons and held items.",
			},
			Weapon_Offhand = {
				name = "Weapon_Offhand",
				recommendedParents = { "LeftHand", "Left Arm" },
				legacyAliases = { "LeftHand" },
				description = "Secondary hand grip for off-hand weapons and shields.",
			},
			Armor_Chest = {
				name = "Armor_Chest",
				recommendedParents = { "Torso", "UpperTorso" },
				legacyAliases = { "Torso" },
				description = "Primary torso anchor for chest armor.",
			},
			Armor_LeftShoulder = {
				name = "Armor_LeftShoulder",
				recommendedParents = { "Left Arm", "LeftUpperArm" },
				description = "Left shoulder armor socket for segmented body pieces.",
			},
			Armor_RightShoulder = {
				name = "Armor_RightShoulder",
				recommendedParents = { "Right Arm", "RightUpperArm" },
				description = "Right shoulder armor socket for segmented body pieces.",
			},
			Armor_LeftHipUpper = {
				name = "Armor_LeftHipUpper",
				recommendedParents = { "Left Leg", "LeftUpperLeg" },
				description = "Upper-left hip armor socket for segmented skirts, belts, and flap pieces.",
			},
			Armor_RightHipUpper = {
				name = "Armor_RightHipUpper",
				recommendedParents = { "Right Leg", "RightUpperLeg" },
				description = "Upper-right hip armor socket for segmented skirts, belts, and flap pieces.",
			},
			Armor_WaistFront = {
				name = "Armor_WaistFront",
				recommendedParents = { "Torso", "UpperTorso" },
				description = "Front waist armor socket for belts or front flap armor.",
			},
			Armor_WaistBack = {
				name = "Armor_WaistBack",
				recommendedParents = { "Torso", "UpperTorso" },
				description = "Back waist armor socket for belts or rear flap armor.",
			},
		},
	},
}

local function getProfileInternal(rigId: string): ItemTypes.RigSocketProfile?
	return profiles[rigId]
end

function RigSocketRegistry.getProfile(rigId: string): ItemTypes.RigSocketProfile?
	return getProfileInternal(rigId)
end

function RigSocketRegistry.getSocket(rigId: string, socketName: string): (ItemTypes.RigSocketDef?, string?)
	local profile = getProfileInternal(rigId)
	if not profile then
		return nil, nil
	end
	local direct = profile.sockets[socketName]
	if direct then
		return direct, socketName
	end
	for canonicalName, socket in pairs(profile.sockets) do
		if socket.legacyAliases then
			for _, alias in ipairs(socket.legacyAliases) do
				if alias == socketName then
					return socket, canonicalName
				end
			end
		end
	end
	return nil, nil
end

function RigSocketRegistry.normalizeSocketName(rigId: string, socketName: string): string?
	local _, canonicalName = RigSocketRegistry.getSocket(rigId, socketName)
	return canonicalName
end

function RigSocketRegistry.getSearchNames(rigId: string, socketName: string): { string }
	local socket, canonicalName = RigSocketRegistry.getSocket(rigId, socketName)
	if not socket or not canonicalName then
		return { socketName }
	end
	local names = { canonicalName }
	if socket.legacyAliases then
		for _, alias in ipairs(socket.legacyAliases) do
			if alias ~= canonicalName then
				table.insert(names, alias)
			end
		end
	end
	return names
end

function RigSocketRegistry.describeSocket(rigId: string, socketName: string): string
	local socket, canonicalName = RigSocketRegistry.getSocket(rigId, socketName)
	if not socket or not canonicalName then
		return socketName
	end
	local parentText = ""
	if socket.recommendedParents and #socket.recommendedParents > 0 then
		parentText = ` (recommended parent: {table.concat(socket.recommendedParents, " / ")})`
	end
	return `{canonicalName}{parentText}`
end

function RigSocketRegistry.list(rigId: string): { ItemTypes.RigSocketDef }
	local profile = getProfileInternal(rigId)
	if not profile then
		return {}
	end
	local out = {}
	for _, socket in pairs(profile.sockets) do
		table.insert(out, socket)
	end
	table.sort(out, function(a, b)
		return a.name < b.name
	end)
	return out
end

return RigSocketRegistry
