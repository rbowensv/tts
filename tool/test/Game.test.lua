-- Tests for mod/src/includes/Game.ttslua, run with standalone Lua:
--
--   npm run test:lua
--
-- Game.ttslua has no TTS dependencies, so it can be loaded directly.

dofile("mod/src/includes/Game.ttslua")

local failures = 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    print("PASS " .. name)
  else
    failures = failures + 1
    print("FAIL " .. name .. "\n  " .. tostring(err))
  end
end

local function eq(actual, expected, label)
  if actual ~= expected then
    error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local function at(game, phase, id, round)
  eq(game.phase, phase, "phase")
  if id then eq(game:currentStep().id, id, "step") end
  if round then eq(game.round, round, "round") end
end

-- Steps forward until the given phase and step, answering any Ready or
-- priority step on the way.
local function advanceTo(game, phase, id)
  for _ = 1, 500 do
    if game.phase == phase and (id == nil or game:currentStep().id == id) then return end
    local step = game:currentStep()
    if step.wait == "ready" then
      game:setReady("Red")
      game:setReady("Blue")
    elseif step.choice == "priority" then
      game:setPriority("Blue")
    else
      game:next()
    end
  end
  error("never reached " .. phase .. " " .. tostring(id))
end

test("a game starts with Setup in round 1", function()
  local game = Game:create({blueSeat = "Red"})
  at(game, "setup", "setupAbilities", 1)
end)

test("Setup ends at Prepared Positions, then round 1's Command Phase", function()
  local game = Game:create({})
  game:next()
  at(game, "setup", "preparedPositions")
  local changed = game:next()
  at(game, "command", "selectCard", 1)
  eq(changed.round, nil, "no new round: round 1 began with Setup")
end)

test("each round is Command, Activation, End", function()
  local game = Game:create({})
  advanceTo(game, "activation")
  at(game, "activation", "activate", 1)
  game:next()
  at(game, "end", "startEffects", 1)
  advanceTo(game, "end", "advanceRound")
  local changed = game:next()
  at(game, "command", "selectCard", 2)
  eq(changed.round, 2, "new round")
end)

test("the game ends after the End Phase of round 5", function()
  local game = Game:create({})
  for round = 1, 4 do
    advanceTo(game, "end", "advanceRound")
    game:next()
    eq(game.round, round + 1, "round")
  end
  advanceTo(game, "end", "advanceRound")
  local changed = game:next()
  eq(changed.over, true, "over")
  eq(game:isOver(), true, "isOver")
  eq(game.round, 5, "stays on round 5")
  eq(#game:next() == 0 and game:isOver(), true, "next after the end does nothing")
end)

test("both seats must be ready before the cards are revealed", function()
  local game = Game:create({})
  advanceTo(game, "command", "selectCard")
  eq(game:setReady("Blue"), false, "one ready")
  at(game, "command", "selectCard")
  eq(game:setReady("Red", true), true, "both ready")
  at(game, "command", "resolveCards")
  eq(game.noCard.Red, true, "red played no card")
end)

test("priority is kept for the round and named in the steps", function()
  local game = Game:create({})
  advanceTo(game, "command", "priority")
  game:setPriority("Red")
  at(game, "command", "nominate")
  eq(game.priority, "Red")
  advanceTo(game, "activation")
  assert(game:text():find("red player"), game:text())
  advanceTo(game, "command", "selectCard")
  eq(game.priority, nil, "cleared for the next round")
end)

test("back undoes steps, across phases and rounds", function()
  local game = Game:create({})
  advanceTo(game, "end", "advanceRound")
  game:next()
  at(game, "command", "selectCard", 2)
  local changed = game:back()
  eq(changed.round, 1, "round changed back")
  at(game, "end", "advanceRound", 1)
  game:back()
  at(game, "end", "endEffects", 1)
end)

test("back to choosing cards clears Ready", function()
  local game = Game:create({})
  advanceTo(game, "command", "selectCard")
  game:setReady("Blue")
  game:setReady("Red")
  game:back()
  at(game, "command", "selectCard")
  eq(game.ready.Blue, nil, "blue")
  eq(game.ready.Red, nil, "red")
end)

test("back with nothing to undo does nothing", function()
  local game = Game:create({})
  eq(game:canGoBack(), false)
  game:back()
  at(game, "setup", "setupAbilities", 1)
end)

test("a saved game carries on where it was", function()
  local game = Game:create({blueSeat = "Red"})
  advanceTo(game, "command", "priority")
  game:setPriority("Blue")
  local copy = Game:load(game:save())
  at(copy, "command", "nominate", 1)
  eq(copy.blueSeat, "Red", "blue seat")
  eq(copy.priority, "Blue", "priority")
  copy:back()
  at(copy, "command", "priority")
end)

test("a save that isn't a game loads as none, a stale step restarts its phase", function()
  eq(Game:load(nil), nil, "nil")
  eq(Game:load("text"), nil, "text")
  local game = Game:load({phase = "end", step = 99, round = 3})
  at(game, "end", "startEffects", 3)
  game = Game:load({phase = "nonsense", step = 1, round = 2})
  at(game, "command", "selectCard", 2)
end)

test("seats and roles", function()
  local game = Game:create({blueSeat = "Red"})
  eq(game:seatOf("Blue"), "Red")
  eq(game:seatOf("Red"), "Blue")
  eq(game:roleOf("Red"), "Blue")
  eq(game:roleOf("Blue"), "Red")
end)

test("the winner has more VP, a tie has none", function()
  eq(Game.winner(8, 5), "Blue")
  eq(Game.winner(3, 9), "Red")
  eq(Game.winner(6, 6), nil)
end)

local function card(pip) return {guid = "g" .. tostring(pip), name = "Card", pip = pip} end

-- Both seats reveal (nil card: No Card); blue player at the Red seat.
local function reveal(game, blueCard, redCard)
  advanceTo(game, "command", "selectCard")
  game:setReady(game:seatOf("Blue"), blueCard == nil, blueCard)
  game:setReady(game:seatOf("Red"), redCard == nil, redCard)
  at(game, "command", "resolveCards")
end

test("the played cards are kept by seat until the next Command Phase", function()
  local game = Game:create({blueSeat = "Red"})
  reveal(game, card(2), nil)
  eq(game.played.Red.pip, 2, "blue player's card, at the Red seat")
  eq(game.played.Blue, nil, "no card")
  advanceTo(game, "end", "advanceRound")
  eq(game.played.Red.pip, 2, "still known in the End Phase")
  game:next()
  eq(next(game.played), nil, "cleared for the next round")
end)

test("fewer pips chooses priority", function()
  local game = Game:create({blueSeat = "Red"})
  reveal(game, card(3), card(1))
  local state = game:priorityState()
  eq(state.mode, "choose")
  eq(state.chooser, "Red")
end)

test("only one card played: that player has priority", function()
  local game = Game:create({})
  reveal(game, nil, card(4))
  local state = game:priorityState()
  eq(state.mode, "given")
  eq(state.role, "Red")
end)

test("same pips: the blue player rolls, a block chooses", function()
  local game = Game:create({})
  reveal(game, card(2), card(2))
  game:next()
  local state = game:priorityState()
  eq(state.mode, "roll")
  eq(state.roller, "Blue")
  game:setRoll("block")
  eq(game:priorityState().chooser, "Blue", "block")
  game:back()
  eq(game:priorityState().mode, "roll", "back undoes the roll")
  game:setRoll("other")
  eq(game:priorityState().chooser, "Red", "other")
end)

test("no cards at all: roll", function()
  local game = Game:create({})
  reveal(game, nil, nil)
  eq(game:priorityState().mode, "roll")
end)

test("unknown pips: the players say", function()
  local game = Game:create({})
  reveal(game, card(nil), card(2))
  eq(game:priorityState().mode, "open")
end)

test("back to choosing cards forgets them", function()
  local game = Game:create({})
  reveal(game, card(1), card(2))
  game:back()
  at(game, "command", "selectCard")
  eq(next(game.played), nil)
end)

test("the pass pool goes to the side with fewer units", function()
  local role, count = Game.passPoolFor(6, 9)
  eq(role, "Blue") eq(count, 3)
  role, count = Game.passPoolFor(7, 5)
  eq(role, "Red") eq(count, 2)
  role, count = Game.passPoolFor(4, 4)
  eq(role, nil) eq(count, 0)
end)

test("units and pass pool are saved and undone", function()
  local game = Game:create({})
  advanceTo(game, "command", "passPool")
  game.units = {Blue = 5, Red = 7}
  game.passPool = {seat = "Blue", guids = {"a", "b"}}
  local copy = Game:load(game:save())
  eq(copy.units.Red, 7, "units")
  eq(copy.passPool.guids[2], "b", "pool")
  game:next()
  game:back()
  eq(game.passPool.seat, "Blue", "back keeps the pool of that step")
end)

if failures > 0 then
  print(failures .. " test(s) failed")
  os.exit(1)
end
print("All tests passed")
