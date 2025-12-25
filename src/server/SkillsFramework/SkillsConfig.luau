local SkillsFolder = script.Parent.Skills
local SkillsDataFolder = script.Parent.SkillsData

local SkillsConfig = {}

export type SkillData = {
	name: string,
	description: string,
	cooldown: number,
	gcd: number,
	level: number,
	animCategory: string?, -- category tag for NPC animation selection
	tags: { string }?,
	cost: number?,
	costs: { number }?,
	baseResource: any?,
	baseDuration: number?,
	castSounds: { string }?, -- Array of sound asset IDs for cast/start (plays random)
	hitSounds: { string }?, -- Array of sound asset IDs for hit impacts (plays random)
	cooldownOnCancel: boolean?,
	combo: {
		steps: number,
		window: number,
		stepDelays: { number }?,
		hitDelays: { number }?,
		recovery: number?, -- optional post-final-hit lock before execution completes (keeps GCD/cooldown from starting early)
		comboCooldown: number?,
		stepDurations: { number }?,
	}?,
	hits: {
		{
			t: number,
			yaw: number,
			coneAngle: number,
			coneRange: number,
			playersOnly: boolean?,
			damageMult: number?,
		}
	}?,
}

export type SkillConfigOverride = {
	name: string?,
	description: string?,
	cooldown: number?,
	gcd: number?,
	level: number?,
	animCategory: string?,
	tags: { string }?,
	cost: number?,
	costs: { number }?,
	baseResource: any?,
	baseDuration: number?,
	castSounds: { string }?,
	hitSounds: { string }?,
	cooldownOnCancel: boolean?,
	combo: {
		steps: number?,
		window: number?,
		stepDelays: { number }?,
		hitDelays: { number }?,
		recovery: number?,
		comboCooldown: number?,
		stepDurations: { number }?,
	}?,
	hits: {
		{
			t: number?,
			yaw: number?,
			coneAngle: number?,
			coneRange: number?,
			playersOnly: boolean?,
			damageMult: number?,
		}
	}?,
}

-- Build skills table by loading all modules under SkillsData
local skills: { [string]: SkillData } = {}
for _, child in ipairs(SkillsDataFolder:GetChildren()) do
	if child:IsA("ModuleScript") then
		local ok, dataOrErr = pcall(require, child)
		if ok and type(dataOrErr) == "table" then
			local name = (dataOrErr.name :: string?) or child.Name
			if name then
				skills[name] = dataOrErr :: SkillData
			end
		else
			warn("SkillsConfig: failed to load skill data from", child:GetFullName(), dataOrErr)
		end
	end
end
SkillsConfig.skills = skills

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for k, v in pairs(value) do
		result[k] = deepCopy(v)
	end
	return result
end

local function deepMerge(destination, source)
	for key, value in pairs(source) do
		if type(value) == "table" then
			local existing = destination[key]
			if type(existing) == "table" then
				destination[key] = deepMerge(existing, value)
			else
				destination[key] = deepCopy(value)
			end
		else
			destination[key] = value
		end
	end
	return destination
end

function SkillsConfig.addSkill(caster: string, name: string, override: SkillConfigOverride?)
	local skillData = SkillsConfig.skills[name]
	if not skillData then
		error(`Skill '{name}' does not exist in SkillsConfig`)
	end

	local config = deepCopy(skillData)
	if override then
		config = deepMerge(config, override)
	end

	local SkillClass = require(SkillsFolder:WaitForChild(name))
	return SkillClass.new(caster, config)
end

return SkillsConfig
