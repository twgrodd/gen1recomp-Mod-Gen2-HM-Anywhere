-- HM Anywhere for Pokémon Gold / Silver v2.8.1
--
-- This mod adds an HM-only field-use menu for Gold/Silver. It deliberately
-- does not teach moves, modify the party, or change battle moves. The normal
-- Gold/Silver badge and map/terrain checks remain in charge.
--
-- The field-move execution order below is intentional and has been tested
-- against Gen1Recomp++ 0.2.24. The important ordering is:
--   HM list closes -> queue the native field action -> close Start menu.
-- Do not move the field-action call to a later core.update: the Gen2 menu
-- facade is the part that successfully queues the action while Start is open.
return function(mod)
  local HM_ORDER = {"CUT", "FLY", "SURF", "STRENGTH", "FLASH", "WHIRLPOOL", "WATERFALL"}
  local HM_ITEMS = {
    CUT="HM_CUT", FLY="HM_FLY", SURF="HM_SURF", STRENGTH="HM_STRENGTH",
    FLASH="HM_FLASH", WHIRLPOOL="HM_WHIRLPOOL", WATERFALL="HM_WATERFALL",
  }

  local function ownsHM(game, move)
    local inv = game and game.save and game.save.inventory or {}
    local id = HM_ITEMS[move]
    return id and (inv[id] or 0) > 0
  end

  local function anyHM(game)
    for _, move in ipairs(HM_ORDER) do
      if ownsHM(game, move) then return true end
    end
    return false
  end

  local function syntheticMon(move)
    -- The Gen 2 Fly presentation uses the field-move source species for the
    -- flying animation. Pidgeot is used for FLY so the native effect shows a
    -- bird. The temporary object is never inserted into the player's party or save.
    local species = (move == "FLY") and "PIDGEOT" or "POLIWAG"
    return { species=species, id=species, nickname="YOU", moves={{id=move}} }
  end

  -- Contextual field use (for example, pressing A while facing a tree or water)
  -- still goes through the engine's normal eligibility check. Vanilla gets
  -- first refusal. If no party Pokémon can perform the move, we provide a
  -- temporary field-move source when the matching HM is in the Bag.
  mod.hooks:wrap("fieldmove.eligibility", function(next, moveId, ctx)
    local mon = next(moveId, ctx)
    if mon then return mon end
    local game = mod._game
    if game and ownsHM(game, moveId) then
      return syntheticMon(moveId)
    end
    return nil
  end)

  -- Menu execution for the ordinary HMs intentionally follows the working
  -- Gen1Recomp++ field-action path: request the action while the HM list is
  -- closing but before the underlying Start menu is popped. The engine then
  -- completes the queued action when the overworld regains control. Do not
  -- move this call into a later core.update callback.
  local function useMove(game, move)
    local ow = game and game.overworld

    -- These direct helpers are kept for CUT/SURF because they are the proven
    -- Gold/Silver path used by the working releases of this mod.
    if ow and move == "CUT"
       and type(ow.useCutFieldMove) == "function"
       and type(ow.tryCut) == "function" then
      if ow:useCutFieldMove() ~= "ok" then return false end
      local x, y = ow.player:facingCell()
      ow:tryCut(x, y)
      return true
    end
    if ow and move == "SURF"
       and type(ow.useSurfFieldMove) == "function"
       and type(ow.trySurf) == "function" then
      if ow:useSurfFieldMove() ~= "ok" then return false end
      local x, y = ow.player:facingCell()
      ow:trySurf(x, y)
      return true
    end

    if mod.world
       and type(mod.world.availableFieldActions) == "function"
       and type(mod.world.useFieldAction) == "function" then
      local wanted = string.lower(move)
      for _, action in ipairs(mod.world:availableFieldActions() or {}) do
        if action.id == wanted then
          local ok = mod.world:useFieldAction(action.id)
          return ok ~= nil and ok ~= false
        end
      end
    end

    -- FLY is handled separately below. Its destination UI is an internal
    -- Gold/Silver screen and is not exposed through the generic field-action
    -- facade on all supported Gen2 builds.
    if ow and move == "FLY" and type(ow.useFlyFieldMove) == "function" then
      return ow:useFlyFieldMove() == "ok"
    end
    return false
  end

  local function useFlyAfterMenus(game)
    local ow = game and game.world
    if not ow then return false end

    -- Current Gold/Silver native implementation: useFieldMove() creates the
    -- real FieldMoves.flyFromMenu result, and the overworld drains it once the
    -- menus are gone.  This must be called only after Start is popped.
    if type(ow.useFieldMove) == "function" then
      local result = ow:useFieldMove("FLY", syntheticMon("FLY"))
      return result and result.ok == true
    end

    if type(ow.openFlyMap) == "function" then
      return ow:openFlyMap() ~= false
    end
    return false
  end

  mod.content.screens:register("HMAnywhereMenu", {
    new = function(game)
      local rows = {}
      for _, move in ipairs(HM_ORDER) do
        if ownsHM(game, move) then
          rows[#rows + 1] = { label=move, value=move }
        end
      end

      local menu
      menu = mod.ui.ListMenu.new(game, "HM", rows, {
        kind="hm_anywhere_menu",
        onChoose=function(item)
          local move = item and item.value
          if not move or not ownsHM(game, move) then return end

          -- The HM list is the top state. Close it first so the normal Start
          -- menu remains underneath while the ordinary field action is queued.
          menu:close()

          if move == "FLY" then
            -- FLY is special: its native destination screen must be opened with
            -- the overworld active, so remove Start before calling the Gen2 World.
            if game.stack and type(game.stack.pop) == "function" then
              game.stack:pop()
            end
            useFlyAfterMenus(game)
            return
          end

          -- Critical ordering for the ordinary HMs:
          --   1) close HM list
          --   2) invoke the working field-action facade
          --   3) close Start menu
          -- The action is queued by step 2 and drained when step 3 restores the
          -- overworld.  Do NOT defer step 2 to core.update.
          useMove(game, move)

          if game.stack and type(game.stack.pop) == "function" then
            game.stack:pop()
          end
        end,
      })
      return menu
    end,
  })

  mod.events:on("game.ready", function(ev)
    mod._game = (ev and ev.game) or mod._game
  end)

  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    mod._game = game
    local out = next(game, items) or items
    if not anyHM(game) then return out end
    for _, item in ipairs(out) do
      if tostring(item.label or ""):upper() == "HM" then return out end
    end
    mod.ui.insertBefore(out, "OPTION", {
      label="HM", desc={"Use your", "HMs"},
      onSelect=function(g)
        mod.ui.push(g, "HMAnywhereMenu")
      end,
    })
    return out
  end)

  mod.log:info("HM Anywhere 2.8.1 loaded for Gold/Silver")
end
