--!strict
-- tools/bake/lounge_classic/Style: THE GILDED ACORN's dimensions (the venue's local frame, studs; floor at Y 0)
-- and its palette: walnut and mahogany, oxblood leather, brass, cream plaster, black-and-gold front.
-- Interface: constants only. No side effects on require.

local Style = {}

-- the hall
Style.WALL = 1 -- brick walls (Roblox: at least 1 stud against light leaks)
Style.OUTER_X = 25 -- the footprint's half width
Style.FRONT_D, Style.BACK_D = -28, 28 -- the footprint's front and back faces
Style.INNER_X = Style.OUTER_X - Style.WALL
Style.INNER_BACK = Style.BACK_D - Style.WALL
Style.CEILING = 13 -- the hall's ceiling (underside)
Style.ROOF_TOP = 14.2 -- the roof deck's top
Style.PARAPET = 16 -- the brick walls' top
Style.CREST = 21.5 -- the acorn's top on the front parapet (the plan's height is 22)

-- the recessed entry: an alcove in the front, four steps up to the double door
Style.ALCOVE_X = 5 -- the alcove's half width (inside its side walls)
Style.DOOR_D = -22 -- the door wall's outer face (the alcove's back)
Style.DOOR_HALF = 3 -- the double door's half width
Style.DOOR_TOP = 8
Style.ALCOVE_TOP = 10 -- the alcove's ceiling
Style.LANDING_D = -25 -- the landing in front of the door, from here to the door
Style.RISE = 0.62 -- each of the four steps

-- outside: the forecourt where the guards stand (to Bowl Lane's planned sidewalk at D -32)
Style.FORECOURT_D = -32
Style.FORECOURT_X = 11
Style.FORECOURT_Y = -2.4 -- its top: the ground at the door is 2.47 below the floor

Style.SIGN = "THE GILDED ACORN"
Style.MENU = "HOT COCOA  ·  COFFEE  ·  GREEN TEA  ·  SNOW CONES"

-- the room (the venue's anchors: the bar at D 16, the bartender at D 20, the booths at X +-18, D -10 and 4)
Style.WAINSCOT = 4 -- the walnut panelling's top
Style.CROWN = 12.2 -- the crown moulding's foot
Style.BAR_X = 12 -- the bar counter's half length
Style.BAR_D0, Style.BAR_D1 = 15, 17 -- its front and back faces
Style.BAR_TOP = 3.35 -- the polished top's top
Style.BACKBAR_D = 24.5 -- the back bar's front face
Style.BARTENDER = { 0, 20 } -- where the bartender stands (X, D)
Style.STOOLS_D = 13.2
Style.STOOL_GAP = 3.4 -- a person (2 studs wide) fits between two stools
Style.BOOTHS = { { -18, -10 }, { 18, -10 }, { -18, 4 }, { 18, 4 } } -- each booth's centre (X, D)
Style.BOOTH_X0, Style.BOOTH_X1 = 13.2, 23.75 -- a booth's reach from the middle (|X|)
Style.TABLES = { { -6, -12 }, { 6, -12 }, { -6, -1 }, { 6, -1 } } -- the club chairs' small tables (X, D)
Style.STAGE = { x0 = -24, x1 = -14, d0 = 14, d1 = 27, top = 1.2 } -- the stage (back left)
Style.PIANO = { -19, 20 } -- the grand piano's centre (X, D)
Style.FIRE_D = 20 -- the fireplace's centre on the east wall
Style.CHANDELIERS = { { 0, -12 }, { 0, 2 } }
Style.PENDANTS = { -8, 0, 8 } -- over the bar (X)
Style.SCONCES = { -17, -3, 11 } -- on both side walls (D)

-- palette
Style.BRICK = { 112, 58, 48 }
Style.MORTAR = { 150, 140, 128 }
Style.STONE = { 168, 160, 146 }
Style.BLACK = { 26, 24, 26 }
Style.GOLD = { 214, 176, 98 }
Style.BRASS = { 190, 152, 78 }
Style.WALNUT = { 86, 54, 36 }
Style.MAHOGANY = { 104, 44, 34 }
Style.DARK_WOOD = { 58, 38, 28 }
Style.LEATHER = { 110, 36, 32 } -- oxblood
Style.TAN = { 150, 96, 60 } -- tan leather
Style.PLASTER = { 232, 218, 190 }
Style.PAPER = { 88, 34, 40 } -- deep claret wallpaper
Style.VELVET = { 120, 22, 34 }
Style.RUG = { 98, 30, 36 }
Style.RUG_BORDER = { 176, 140, 76 }
Style.IVORY = { 240, 232, 214 }
Style.CHINA = { 244, 240, 232 }
Style.COPPER = { 176, 102, 64 }
Style.LAMP = { 255, 196, 132 }
Style.AMBER = { 214, 150, 72 }
Style.FIRE = { 255, 128, 40 }

return Style
