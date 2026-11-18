"""Optional, reversible Whack-a-Mole play mode for Blender 4.3+.

Open this text in Blender's Text Editor and choose Run Script (Alt-P).
In a 3D View, open Sidebar (N) > Arcade > Start 45-second round, or F3 and
search for "Play Whack a Mole". Click a raised mole or press 1, 2, 3, 4, 5.
Esc ends the round and restores the saved demonstration pose and animation.

This script does not run on file load, access the network, save files, or
install dependencies. Its registration and score history last this session.
"""

import math
import random
import time

import bpy
from bpy_extras import view3d_utils


ROUND_SECONDS = 45.0
POP_HEIGHT = 0.30
RISE_SECONDS = 0.13
FALL_SECONDS = 0.14
ROOT_NAMES = tuple("Mole_%02d_ROOT" % number for number in range(1, 6))
KEY_TO_MOLE = {
    "ONE": 1, "TWO": 2, "THREE": 3, "FOUR": 4, "FIVE": 5,
    "NUMPAD_1": 1, "NUMPAD_2": 2, "NUMPAD_3": 3,
    "NUMPAD_4": 4, "NUMPAD_5": 5,
}
_RUNTIME_KEY = "WHACK_A_MOLE_ARCADE_SESSION_V1"


def _runtime():
    return bpy.app.driver_namespace.setdefault(
        _RUNTIME_KEY, {"active": None, "last_score": None, "classes": []}
    )


def _smooth(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


class RoundState:
    """Clock-driven rules, independent of Blender UI and frame rate."""

    def __init__(self, now, rng=None):
        self.rng = rng if rng is not None else random.Random()
        self.started = now
        self.score = 0
        self.hits = 0
        self.misses = 0
        self.active = None
        self.last_mole = None
        self.next_pop = now + 0.65
        self.notice = "CLICK A MOLE / 1-5"
        self.notice_until = now + 2.0

    def remaining(self, now):
        return max(0.0, ROUND_SECONDS - (now - self.started))

    def finished(self, now):
        return now - self.started >= ROUND_SECONDS

    def height(self, mole_id, now):
        active = self.active
        if not active or active["mole"] != mole_id:
            return 0.0
        if now < active["close"]:
            return POP_HEIGHT * _smooth((now - active["open"]) / RISE_SECONDS)
        return active["fall_from"] * (
            1.0 - _smooth((now - active["close"]) / FALL_SECONDS)
        )

    def advance(self, now):
        if self.finished(now):
            self.active = None
            return
        if self.active and now >= self.active["close"] + FALL_SECONDS:
            self.active = None
        if self.active is None and now >= self.next_pop:
            candidates = [number for number in range(1, 6) if number != self.last_mole]
            mole_id = self.rng.choice(candidates)
            progress = min(1.0, (now - self.started) / ROUND_SECONDS)
            duration = self.rng.uniform(1.05, 1.35) - progress * 0.48
            self.active = {
                "mole": mole_id,
                "open": now,
                "close": now + duration,
                "hit": False,
                "fall_from": POP_HEIGHT,
            }
            self.last_mole = mole_id
            self.next_pop = now + duration + FALL_SECONDS + max(0.12, 0.36 - progress * 0.22)

    def strike(self, mole_id, now):
        if self.finished(now):
            return False
        active = self.active
        hit = bool(
            active
            and mole_id == active["mole"]
            and not active["hit"]
            and now < active["close"]
            and self.height(mole_id, now) >= POP_HEIGHT * 0.35
        )
        if hit:
            active["fall_from"] = self.height(mole_id, now)
            active["hit"] = True
            active["close"] = now
            self.next_pop = now + FALL_SECONDS + 0.21
            self.score += 10
            self.hits += 1
            self.notice = "NICE! +10"
        else:
            self.score = max(0, self.score - 2)
            self.misses += 1
            self.notice = "MISS -2"
        self.notice_until = now + 0.55
        return hit


def _view_in_window(window, preferred=None):
    if not window or not window.screen:
        return None, None
    areas = list(window.screen.areas)
    if preferred in areas:
        areas.remove(preferred)
        areas.insert(0, preferred)
    for area in areas:
        if area.type == "VIEW_3D":
            region = next((r for r in area.regions if r.type == "WINDOW"), None)
            if region is not None:
                return area, region
    return None, None


def _descendants(root):
    yield root
    for child in root.children:
        yield from _descendants(child)


def _remember_animation(owner):
    data = owner.animation_data
    if data is None:
        return None
    record = {
        "owner": owner,
        "action": data.action,
        "slot": getattr(data, "action_slot", None),
        "tracks": [(track, track.mute) for track in data.nla_tracks],
        "drivers": [(driver, driver.mute) for driver in data.drivers],
    }
    return record


def _pause_animation(record):
    data = record["owner"].animation_data
    data.action = None
    for track, _ in record["tracks"]:
        track.mute = True
    for driver, _ in record["drivers"]:
        driver.mute = True


def _restore_animation(record):
    data = record["owner"].animation_data
    if data is None:
        data = record["owner"].animation_data_create()
    data.action = record["action"]
    if record["slot"] is not None and hasattr(data, "action_slot"):
        data.action_slot = record["slot"]
    for track, mute in record["tracks"]:
        track.mute = mute
    for driver, mute in record["drivers"]:
        driver.mute = mute


def _before_save_or_load(_unused):
    # A user can choose File > Save while the modal is running. Restore first,
    # so a save never captures disconnected animation or temporary game poses.
    active = _runtime().get("active")
    if active is not None:
        active.stop(bpy.context, cancelled=True)


class ARCADE_OT_play_whack_a_mole(bpy.types.Operator):
    bl_idname = "arcade.play_whack_a_mole"
    bl_label = "Play Whack a Mole"
    bl_description = "Play for 45 seconds; click moles or press 1-5; Esc restores the demonstration"
    bl_options = {"BLOCKING"}

    _timer = None
    _running = False

    @classmethod
    def poll(cls, context):
        return context.window is not None and _runtime().get("active") is None

    def execute(self, context):
        return self.invoke(context, None)

    def invoke(self, context, event):
        self._window = context.window
        self._area, self._region = _view_in_window(self._window, context.area)
        if self._area is None:
            self.report({"ERROR"}, "Open a 3D View in this Blender window before starting.")
            return {"CANCELLED"}
        self._scene = context.scene
        self._view_layer = context.view_layer
        missing = [name for name in ROOT_NAMES if name not in self._scene.objects]
        if missing:
            self.report({"ERROR"}, "This scene is missing mole roots: " + ", ".join(missing))
            return {"CANCELLED"}
        self._roots = [self._scene.objects[name] for name in ROOT_NAMES]
        objects = set()
        for root in self._roots:
            objects.update(_descendants(root))
        mallet = self._scene.objects.get("Mallet_ROOT")
        if mallet is not None:
            objects.update(_descendants(mallet))
        self._texts = {}
        for name in ("Score_Text", "Time_Text", "Status_Text"):
            obj = self._scene.objects.get(name)
            if obj is not None and obj.type == "FONT":
                self._texts[name] = obj
                objects.add(obj)

        owners = [self._scene] + list(objects)
        for obj in objects:
            if obj.data is not None:
                owners.append(obj.data)
        owners = list({id(owner): owner for owner in owners}.values())
        if any(getattr(owner.animation_data, "use_tweak_mode", False) for owner in owners):
            self.report({"ERROR"}, "Exit NLA Tweak Mode before starting a round.")
            return {"CANCELLED"}

        self._animation = [r for r in (_remember_animation(o) for o in owners) if r is not None]
        self._objects = [
            (obj, obj.matrix_basis.copy(), obj.hide_viewport, obj.hide_render,
             obj.hide_get(view_layer=self._view_layer))
            for obj in objects
        ]
        self._text_bodies = [(obj.data, obj.data.body) for obj in self._texts.values()]
        self._frame = self._scene.frame_current
        self._subframe = self._scene.frame_subframe
        self._was_playing = bool(self._window.screen.is_animation_playing)
        self._wm = context.window_manager
        self._running = True
        try:
            if self._was_playing:
                with context.temp_override(window=self._window, area=self._area, region=self._region):
                    bpy.ops.screen.animation_cancel(restore_frame=False)
            for record in self._animation:
                _pause_animation(record)
            for root in self._roots:
                root.location.z = 0.0
            self._game = RoundState(time.monotonic())
            self._last_board = None
            self._timer = self._wm.event_timer_add(1.0 / 50.0, window=self._window)
            self._wm.modal_handler_add(self)
            _runtime()["active"] = self
            self._draw_state(time.monotonic())
        except Exception as error:
            self.stop(context, cancelled=True)
            self.report({"ERROR"}, "Could not start round: " + str(error))
            return {"CANCELLED"}
        self.report({"INFO"}, "Whack-a-Mole: click raised moles or press 1-5. Esc restores the scene.")
        return {"RUNNING_MODAL"}

    def _draw_state(self, now):
        for index, root in enumerate(self._roots, 1):
            root.location.z = self._game.height(index, now)
        board = (
            self._game.score,
            int(math.ceil(self._game.remaining(now))),
            self._game.notice if now < self._game.notice_until else "WHACK A MOLE!",
        )
        if board != self._last_board:
            for name, value in zip(
                ("Score_Text", "Time_Text", "Status_Text"),
                ("%04d" % board[0], "%02d" % board[1], board[2]),
            ):
                obj = self._texts.get(name)
                if obj is not None:
                    obj.data.body = value
            self._last_board = board
        self._area.tag_redraw()

    def _mouse_mole(self, context, event):
        region = self._region
        point = (event.mouse_x - region.x, event.mouse_y - region.y)
        if not (0 <= point[0] < region.width and 0 <= point[1] < region.height):
            return False, None
        space = self._area.spaces.active
        region_3d = space.region_3d
        if region_3d is None:
            return False, None
        origin = view3d_utils.region_2d_to_origin_3d(region, region_3d, point)
        direction = view3d_utils.region_2d_to_vector_3d(region, region_3d, point)
        depsgraph = context.evaluated_depsgraph_get()
        hit, _, _, _, obj, _ = self._scene.ray_cast(depsgraph, origin, direction, distance=1000.0)
        if not hit:
            return True, None
        obj = getattr(obj, "original", obj)
        while obj is not None:
            value = obj.get("mole_id")
            if isinstance(value, (int, float)) and int(value) in range(1, 6):
                return True, int(value)
            if obj.name in ROOT_NAMES:
                return True, ROOT_NAMES.index(obj.name) + 1
            obj = obj.parent
        return True, None

    def modal(self, context, event):
        if not self._running:
            return {"CANCELLED"}
        try:
            if context.scene != self._scene or self._area.type != "VIEW_3D":
                self.stop(context, cancelled=True)
                return {"CANCELLED"}
            if event.type == "ESC" and event.value == "PRESS":
                self.stop(context, cancelled=True)
                return {"CANCELLED"}
            now = time.monotonic()
            if self._game.finished(now):
                score, hits = self._game.score, self._game.hits
                self.stop(context, cancelled=False)
                self.report({"INFO"}, "Round complete: %d points, %d hits. Play again from the Arcade sidebar." % (score, hits))
                return {"FINISHED"}
            # Blender 4.3 Event does not expose the originating Timer object.
            # All timer events are safe here: state uses the monotonic clock,
            # rather than counting events, so another timer cannot speed play up.
            if event.type == "TIMER":
                self._game.advance(now)
                self._draw_state(now)
                return {"RUNNING_MODAL"}
            if event.value == "PRESS" and not getattr(event, "is_repeat", False):
                if event.type in KEY_TO_MOLE:
                    self._game.strike(KEY_TO_MOLE[event.type], now)
                    self._draw_state(now)
                    return {"RUNNING_MODAL"}
                if event.type == "LEFTMOUSE":
                    inside, mole_id = self._mouse_mole(context, event)
                    if inside:
                        self._game.strike(mole_id, now)
                        self._draw_state(now)
                        return {"RUNNING_MODAL"}
            # View orbit/pan/zoom and sidebar buttons remain available.
            return {"PASS_THROUGH"}
        except (ReferenceError, RuntimeError, AttributeError) as error:
            self.stop(context, cancelled=True)
            self.report({"WARNING"}, "Round stopped safely: " + str(error))
            return {"CANCELLED"}

    def stop(self, context, cancelled=True):
        if not self._running:
            return
        self._running = False
        if self._timer is not None:
            try:
                self._wm.event_timer_remove(self._timer)
            except (ReferenceError, RuntimeError):
                pass
            self._timer = None
        runtime = _runtime()
        if hasattr(self, "_game"):
            runtime["last_score"] = {
                "score": self._game.score,
                "hits": self._game.hits,
                "misses": self._game.misses,
                "cancelled": cancelled,
            }
        if runtime.get("active") is self:
            runtime["active"] = None
        for record in getattr(self, "_animation", []):
            try:
                _restore_animation(record)
            except (ReferenceError, RuntimeError):
                pass
        try:
            self._scene.frame_set(self._frame, subframe=self._subframe)
        except (ReferenceError, RuntimeError):
            pass
        for obj, matrix, hide_viewport, hide_render, hide in getattr(self, "_objects", []):
            try:
                obj.matrix_basis = matrix
                obj.hide_viewport = hide_viewport
                obj.hide_render = hide_render
                obj.hide_set(hide, view_layer=self._view_layer)
            except (ReferenceError, RuntimeError):
                pass
        for data, body in getattr(self, "_text_bodies", []):
            try:
                data.body = body
            except (ReferenceError, RuntimeError):
                pass
        try:
            self._view_layer.update()
            self._area.tag_redraw()
            if self._was_playing and not self._window.screen.is_animation_playing:
                with context.temp_override(window=self._window, area=self._area, region=self._region):
                    bpy.ops.screen.animation_play()
        except (ReferenceError, RuntimeError):
            pass

    def cancel(self, context):
        self.stop(context, cancelled=True)


class ARCADE_OT_stop_whack_a_mole(bpy.types.Operator):
    bl_idname = "arcade.stop_whack_a_mole"
    bl_label = "Stop and Restore Demo"
    bl_description = "Stop the current round and restore the project's original animation and pose"

    def execute(self, context):
        active = _runtime().get("active")
        if active is not None:
            active.stop(context, cancelled=True)
        return {"FINISHED"}


class ARCADE_PT_whack_a_mole(bpy.types.Panel):
    bl_label = "Whack-a-Mole"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "Arcade"

    def draw(self, context):
        layout = self.layout
        runtime = _runtime()
        active = runtime.get("active")
        if active is not None and active._running:
            game = active._game
            layout.label(text="Score: %d" % game.score)
            layout.label(text="Time: %02d seconds" % math.ceil(game.remaining(time.monotonic())))
            layout.operator("arcade.stop_whack_a_mole", icon="CANCEL")
        else:
            layout.operator("arcade.play_whack_a_mole", text="Start 45-second round", icon="PLAY")
            result = runtime.get("last_score")
            if result is not None:
                title = "Stopped round" if result["cancelled"] else "Last round"
                layout.label(text="%s: %d points" % (title, result["score"]))
                layout.label(text="%d hits / %d misses" % (result["hits"], result["misses"]))
        layout.separator()
        layout.label(text="Click a raised mole, or press 1-5.")
        layout.label(text="+10 hit / -2 miss (minimum 0)")
        layout.label(text="Esc stops and restores the demo.")
        layout.label(text="Back row: 1, 2, 3; front: 4, 5.")


CLASSES = (ARCADE_OT_play_whack_a_mole, ARCADE_OT_stop_whack_a_mole, ARCADE_PT_whack_a_mole)


def _draw_arcade_menu(self, context):
    self.layout.separator()
    self.layout.operator("arcade.play_whack_a_mole", text="Play Whack a Mole", icon="PLAY")


def unregister():
    runtime = _runtime()
    active = runtime.get("active")
    if active is not None:
        active.stop(bpy.context, cancelled=True)
    for handler in runtime.get("handlers", []):
        for callbacks in (bpy.app.handlers.save_pre, bpy.app.handlers.load_pre):
            if handler in callbacks:
                callbacks.remove(handler)
    runtime["handlers"] = []
    for menu_type, draw_callback in runtime.get("menus", []):
        try:
            menu_type.remove(draw_callback)
        except (RuntimeError, ValueError):
            pass
    runtime["menus"] = []
    for cls in reversed(runtime.get("classes", [])):
        try:
            bpy.utils.unregister_class(cls)
        except RuntimeError:
            pass
    runtime["classes"] = []


def register():
    unregister()
    runtime = _runtime()
    for cls in CLASSES:
        bpy.utils.register_class(cls)
    runtime["classes"] = list(CLASSES)
    bpy.types.VIEW3D_MT_view.append(_draw_arcade_menu)
    runtime["menus"] = [(bpy.types.VIEW3D_MT_view, _draw_arcade_menu)]
    bpy.app.handlers.save_pre.append(_before_save_or_load)
    bpy.app.handlers.load_pre.append(_before_save_or_load)
    runtime["handlers"] = [_before_save_or_load]
    print("Whack-a-Mole ready: 3D View > N > Arcade, or F3 > Play Whack a Mole.")


if __name__ == "__main__":
    register()
