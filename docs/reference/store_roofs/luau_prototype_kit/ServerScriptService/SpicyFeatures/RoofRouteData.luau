-- Spicy Rodent / isolated local roof route data. No global route registry IDs are changed.
-- Y-up meters, local roof coordinates. Replace/transform points as needed in Studio.
local RoofRouteData = {}
RoofRouteData.Version = "RoofKit-v1"
RoofRouteData.Nodes = {
    { id = "west_eave_0", position = Vector3.new(-5.050, 4.190, -5.600), kind = "roof_eave" },
    { id = "west_mid_0", position = Vector3.new(-2.600, 5.954, -5.600), kind = "roof_slope" },
    { id = "west_eave_1", position = Vector3.new(-5.050, 4.190, 0.000), kind = "roof_eave" },
    { id = "west_mid_1", position = Vector3.new(-2.600, 5.954, 0.000), kind = "roof_slope" },
    { id = "west_eave_2", position = Vector3.new(-5.050, 4.190, 5.600), kind = "roof_eave" },
    { id = "west_mid_2", position = Vector3.new(-2.600, 5.954, 5.600), kind = "roof_slope" },
    { id = "east_eave_0", position = Vector3.new(5.050, 4.190, -5.600), kind = "roof_eave" },
    { id = "east_mid_0", position = Vector3.new(2.600, 5.954, -5.600), kind = "roof_slope" },
    { id = "east_eave_1", position = Vector3.new(5.050, 4.190, 0.000), kind = "roof_eave" },
    { id = "east_mid_1", position = Vector3.new(2.600, 5.954, 0.000), kind = "roof_slope" },
    { id = "east_eave_2", position = Vector3.new(5.050, 4.190, 5.600), kind = "roof_eave" },
    { id = "east_mid_2", position = Vector3.new(2.600, 5.954, 5.600), kind = "roof_slope" },
    { id = "ridge_0", position = Vector3.new(0.000, 7.860, -5.600), kind = "ridge_perch" },
    { id = "ridge_1", position = Vector3.new(0.000, 7.860, 0.000), kind = "ridge_perch" },
    { id = "ridge_2", position = Vector3.new(0.000, 7.860, 5.600), kind = "ridge_perch" },
}
RoofRouteData.Edges = {
    { a = "west_eave_0", b = "west_mid_0", travel = "roof_climb", bidirectional = true },
    { a = "west_mid_0", b = "ridge_0", travel = "roof_climb", bidirectional = true },
    { a = "west_eave_1", b = "west_mid_1", travel = "roof_climb", bidirectional = true },
    { a = "west_mid_1", b = "ridge_1", travel = "roof_climb", bidirectional = true },
    { a = "west_eave_2", b = "west_mid_2", travel = "roof_climb", bidirectional = true },
    { a = "west_mid_2", b = "ridge_2", travel = "roof_climb", bidirectional = true },
    { a = "east_eave_0", b = "east_mid_0", travel = "roof_climb", bidirectional = true },
    { a = "east_mid_0", b = "ridge_0", travel = "roof_climb", bidirectional = true },
    { a = "east_eave_1", b = "east_mid_1", travel = "roof_climb", bidirectional = true },
    { a = "east_mid_1", b = "ridge_1", travel = "roof_climb", bidirectional = true },
    { a = "east_eave_2", b = "east_mid_2", travel = "roof_climb", bidirectional = true },
    { a = "east_mid_2", b = "ridge_2", travel = "roof_climb", bidirectional = true },
    { a = "ridge_0", b = "ridge_1", travel = "ridge_run", bidirectional = true },
    { a = "ridge_1", b = "ridge_2", travel = "ridge_run", bidirectional = true },
    { a = "west_eave_0", b = "west_eave_1", travel = "eave_run", bidirectional = true },
    { a = "west_eave_1", b = "west_eave_2", travel = "eave_run", bidirectional = true },
    { a = "east_eave_0", b = "east_eave_1", travel = "eave_run", bidirectional = true },
    { a = "east_eave_1", b = "east_eave_2", travel = "eave_run", bidirectional = true },
}
RoofRouteData.ExternalHooks = {
    { id = "west_wire_hook", from = "west_eave_0", target = nil, kind = "utility_wire_transfer" },
    { id = "east_roof_hook", from = "east_eave_2", target = nil, kind = "adjacent_roof_transfer" },
    { id = "ground_recovery_hook", from = "west_eave_1", target = nil, kind = "recoverable_drop" },
}
return RoofRouteData
