### Goals
Something similar to "ink" by inkle, which can be used in Unity and Unreal Engine
https://github.com/inkle/ink/blob/master/Documentation/WritingWithInk.md

As they don't support roblox studio, it doesn't make sense to recreate the advanced system that they have, but merely take inspiration

We can instead have:
- dialogue written in module scripts:
  - sequential, speaker text -> options for response -> execute functionality if necessary, support nested stuff (branching off the dialogue based on user choice)
  - with the ability to execute functionality, or fire an event to indicate something happend (so listeners can execute functionality)
  - that can represent choices for the user (as a table) for UI to consume and provide a response to continue the dialogue
- a dialogue manager API
    - that can load a dialogue module
    - expose functions to begin the story/dialogue, while also returning user response options
    - continuing, choosing responses if multiple choices exist (perhaps by index/id)

A quest system which can:
- support multiple "quest steps", so quests with multiple phases to complete
- gate quests behind arbitray requirements, i.e. some event was completed, reach a certain level, have certain stats/attributes
- provide arbitary rewards, i.e. equipment, XP, gold, attribute points, consumables, unlock milestones
- handle a quest log, with easy serialization to be able to displayed by UI, as well as a quest completion history
- allow NPCs to provide one time or repeatable quests
- NPCs can provide the option to start multiple quests at once (player picks quests through dialogue)
- guide the user towards the goal of completion, i.e. a marker for a location player needs to go to

### Notes
check out this repo: shapedbyrainstudios/quest-system

I used it in my previous game to develop an extensible quest system paired nicely with a dialogue system that uses ink, a really good implementation that uses an event bus to get everything to work nicely.

It allows arbitrary quest requirements to be made, quest markers, quest steps, and an effective serialization/state system that allows us to save/load quest data, down to the progress in "quest step"s, and integrates ink with the game nicely   

Copilot: read through both the repo and website thoroughly to gain better understanding of what im thinking of. 