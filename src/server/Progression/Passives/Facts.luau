--!strict
-- What passive filters read about a character and an attack, worked out once per hit: what is held,
-- the form in use, which mastery track the attack belongs to, whether it is a combo's last step,
-- how far apart the two are.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BasicAttackForm = require(ReplicatedStorage.Shared.skills.BasicAttackForm)
local BasicAttackProfileRegistry = require(ReplicatedStorage.Shared.skills.BasicAttackProfileRegistry)
local ClientSpec = require(ReplicatedStorage.Shared.skills.ClientSpec)
local MasteryTrees = require(ReplicatedStorage.Shared.progression.MasteryTrees)

local Server = ServerScriptService.Server
local CombatLoadoutService = require(Server.Inventory.CombatLoadout.CombatLoadoutService)
local Registrar = require(Server.Services.Registrar)
local Filters = require(script.Parent.Filters)

local BASIC_ATTACK = "BasicAttack"

local Facts = {}

function Facts.loadoutOf(entityId: string): Filters.Loadout
	local snapshot = CombatLoadoutService.get(entityId)
	local form = BasicAttackForm.resolve(snapshot)
	return {
		context = BasicAttackProfileRegistry.classKeyOf(snapshot),
		infusion = if form.infusion then form.infusion.element else nil,
	}
end

-- The track an attack by `skillId` belongs to, and whether `comboStep` is its last step.
function Facts.attackOf(entityId: string, skillId: string?, comboStep: number?): (string?, boolean)
	if skillId == BASIC_ATTACK then
		local form = BasicAttackForm.resolve(CombatLoadoutService.get(entityId))
		local tree: MasteryTrees.TreeDef? = nil
		if form.shapeNode then
			local _node, shapeTree = MasteryTrees.node(form.shapeNode)
			tree = shapeTree
		end
		local final = comboStep ~= nil and comboStep >= form.profile.combo.steps
		return if tree then tree.track else nil, final
	end
	local spec = if skillId then (ClientSpec :: any)[skillId] else nil
	local mastery = spec and spec.mastery
	return if mastery then mastery.track else nil, false
end

local function positionOf(entityId: string): Vector3?
	local model = Registrar.getEntityById(entityId)
	local root = model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if root then root.Position else nil
end

function Facts.hit(
	sourceId: string,
	targetId: string,
	metadata: { [string]: any },
	result: { byType: { [string]: number }?, critTypes: { [string]: boolean }? }?
): Filters.HitFacts
	local loadout = Facts.loadoutOf(sourceId)
	local skillId = if type(metadata.skillId) == "string" then metadata.skillId else nil
	local comboStep = if type(metadata.comboStep) == "number" then metadata.comboStep else nil
	local track, final = Facts.attackOf(sourceId, skillId, comboStep)
	local from, to = positionOf(sourceId), positionOf(targetId)
	return {
		context = loadout.context,
		infusion = loadout.infusion,
		sourceId = sourceId,
		targetId = targetId,
		skillId = skillId,
		delivery = if type(metadata.delivery) == "string" then metadata.delivery else nil,
		comboStep = comboStep,
		finalStep = final,
		track = track,
		distance = if from and to then (from - to).Magnitude else nil,
		byType = result and result.byType,
		critTypes = result and result.critTypes,
	}
end

return Facts
