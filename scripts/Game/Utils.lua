local Utils = {}

function Utils.dist(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

function Utils.angleBetween(x1, y1, x2, y2)
    return math.atan(y2 - y1, x2 - x1)
end

function Utils.normalizeAngle(a)
    while a > math.pi do a = a - 2 * math.pi end
    while a < -math.pi do a = a + 2 * math.pi end
    return a
end

function Utils.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function Utils.lerp(a, b, t)
    return a + (b - a) * t
end

return Utils
