-- HM Anywhere for Pokemon Gold / Silver v2.4.0
--
-- Based on the execution path proven by v1.8.0.  The important ordering is:
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
    return { species="POLIWAG", id="POLIWAG", nickname="YOU", moves={{id=move}} }
  end

  -- This is the part that makes the normal A-button CUT/SURF/etc. paths work
  -- without a party user.  Vanilla remains first; the synthetic source is only
  -- returned when the player owns the HM.
  mod.hooks:wrap("fieldmove.eligibility", function(next, moveId, ctx)
    local mon = next(moveId, ctx)
    if mon then return mon end
    local game = mod._game
    if game and ownsHM(game, moveId) then
      return syntheticMon(moveId)
    end
    return nil
  end)

  -- Keep this EXACTLY on the v1.8 menu execution seam.  In particular, use the
  -- public field-action facade before the Start menu is popped.  That facade is
  -- what successfully queued CUT/SURF/FLASH in v1.8; calling the internal
  -- World:useFieldMove from core.update was the regression in later versions.
  local function useMove(game, move)
    local ow = game and game.overworld

    -- These two older helpers are retained when present because v1.8 proved
    -- them useful on builds that expose them.
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

    -- FLY is deliberately not mixed into the generic facade fallback.  If the
    -- current engine exposes the internal native move, queue it after the Start
    -- menu is gone (handled by the caller below).  Older builds may expose one
    -- of these direct helpers instead.
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

          -- ListMenu is the top state here.  Pop it first, exactly as v1.8 did.
          menu:close()

          if move == "FLY" then
            -- FLY is special: the native World:useFieldMove path must see the
            -- overworld, not a Start menu.  Pop Start first, then call it.
            if game.stack and type(game.stack.pop) == "function" then
              game.stack:pop()
            end
            useFlyAfterMenus(game)
            return
          end

          -- This is the critical v1.8 ordering:
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

  mod.log:info("HM Anywhere 2.4.0 loaded for Gold/Silver")
end
