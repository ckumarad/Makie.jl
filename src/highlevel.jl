function heatmap(x,y,z, kw_args)
    get!(kw_args, :color_norm, Vec2f0(ignorenan_extrema(z)))
    get!(kw_args, :color_map, Plots.make_gradient(cgrad()))
    delete!(kw_args, :intensity)
    I = GLVisualize.Intensity{Float32}
    heatmap = I[z[j,i] for i=1:size(z, 2), j=1:size(z, 1)]
    tex = GLAbstraction.Texture(heatmap, minfilter=:nearest)
    kw_args[:stroke_width] = 0f0
    kw_args[:levels] = 1f0
    visualize(tex, Style(:default), kw_args)
end


function contour(x, y, z, kw_args)
    if kw_args[:fillrange] != nothing
        delete!(kw_args, :intensity)
        I = GLVisualize.Intensity{Float32}
        main = [I(z[j,i]) for i=1:size(z, 2), j=1:size(z, 1)]
        return visualize(main, Style(:default), kw_args)
    else
        h = kw_args[:levels]
        T = eltype(z)
        levels = Contour.contours(map(T, x), map(T, y), z, h)
        result = Point2f0[]
        zmin, zmax = get(kw_args, :limits, Vec2f0(ignorenan_extrema(z)))
        cmap = get(kw_args, :color_map, get(kw_args, :color, RGBA{Float32}(0,0,0,1)))
        colors = RGBA{Float32}[]
        for c in levels.contours
            for elem in c.lines
                append!(result, elem.vertices)
                push!(result, Point2f0(NaN32))
                col = GLVisualize.color_lookup(cmap, c.level, zmin, zmax)
                append!(colors, fill(col, length(elem.vertices) + 1))
            end
        end
        kw_args[:color] = colors
        kw_args[:color_map] = nothing
        kw_args[:color_norm] = nothing
        kw_args[:intensity] = nothing
        return visualize(result, Style(:lines),kw_args)
    end
end


function surface(x,y,z, kw_args)
    if isa(x, Range) && isa(y, Range)
        main = z
        kw_args[:ranges] = (x, y)
    else
        if isa(x, AbstractMatrix) && isa(y, AbstractMatrix)
            main = map(s->map(Float32, s), (x, y, z))
        elseif isa(x, AbstractVector) || isa(y, AbstractVector)
            x = Float32[x[i] for i = 1:size(z,1), j = 1:size(z,2)]
            y = Float32[y[j] for i = 1:size(z,1), j = 1:size(z,2)]
            main = (x, y, map(Float32, z))
        else
            error("surface: combination of types not supported: $(typeof(x)) $(typeof(y)) $(typeof(z))")
        end
        if get(kw_args, :wireframe, false)
            points = map(Point3f0, zip(vec(x), vec(y), vec(z)))
            faces = Cuint[]
            idx = (i,j) -> sub2ind(size(z), i, j) - 1
            for i=1:size(z,1), j=1:size(z,2)

                i < size(z,1) && push!(faces, idx(i, j), idx(i+1, j))
                j < size(z,2) && push!(faces, idx(i, j), idx(i, j+1))

            end
            color = get(kw_args, :stroke_color, RGBA{Float32}(0,0,0,1))
            kw_args[:color] = color
            kw_args[:thickness] = get(kw_args, :stroke_width, 1f0)
            kw_args[:indices] = faces
            delete!(kw_args, :stroke_color)
            delete!(kw_args, :stroke_width)

            return visualize(points, Style(:linesegment), kw_args)
        end
    end
    return visualize(main, Style(:surface), kw_args)
end


function poly(points, kw_args)
    last(points) == first(points) && pop!(points)
    polys = GeometryTypes.split_intersections(points)
    result = []
    for poly in polys
        mesh = GLNormalMesh(poly) # make polygon
        if !isempty(GeometryTypes.faces(mesh)) # check if polygonation has any faces
            push!(result, GLVisualize.visualize(mesh, Style(:default), kw_args))
        else
            warn("Couldn't draw the polygon: $points")
        end
    end
    result
end



function scatter(points, kw_args)
    prim = get(kw_args, :primitive, GeometryTypes.Circle)
    if isa(prim, GLNormalMesh)
        if haskey(kw_args, :model)
            p = get(kw_args, :perspective, eye(GeometryTypes.Mat4f0))
            kw_args[:scale] = GLAbstraction.const_lift(kw_args[:model], kw_args[:scale], p) do m, sc, p
                s  = Vec3f0(m[1,1], m[2,2], m[3,3])
                ps = Vec3f0(p[1,1], p[2,2], p[3,3])
                r  = sc ./ (s .* ps)
                r
            end
        end
    else # 2D prim
        kw_args[:scale] = to_vec(Vec2f0, kw_args[:scale])
    end

    if haskey(kw_args, :stroke_width)
        s = Reactive.value(kw_args[:scale])
        sw = kw_args[:stroke_width]
        if sw*5 > _cycle(Reactive.value(s), 1)[1] # restrict marker stroke to 1/10th of scale (and handle arrays of scales)
            kw_args[:stroke_width] = s[1] / 5f0
        end
    end
    kw_args[:scale_primitive] = false
    if isa(prim, String)
        kw_args[:position] = points
        if !isa(kw_args[:scale], Vector) # if not vector, we can assume it's relative scale
            kw_args[:relative_scale] = kw_args[:scale]
            delete!(kw_args, :scale)
        end
        return visualize(prim, Style(:default), kw_args)
    end
    visualize((prim, points), Style(:default), kw_args)
end



function image(img, kw_args)
    rect = kw_args[:primitive]
    kw_args[:primitive] = GeometryTypes.SimpleRectangle{Float32}(rect.x, rect.y, rect.h, rect.w) # seems to be flipped
    visualize(img, Style(:default), kw_args)
end

function handle_segment{P}(lines, line_segments, points::Vector{P}, segment)
    (isempty(segment) || length(segment) < 2) && return
    if length(segment) == 2
         append!(line_segments, view(points, segment))
    elseif length(segment) == 3
        p = view(points, segment)
        push!(line_segments, p[1], p[2], p[2], p[3])
    else
        append!(lines, view(points, segment))
        push!(lines, P(NaN))
    end
end

function lines(points, kw_args)
    result = []
    isempty(points) && return result
    P = eltype(points)
    lines = P[]
    line_segments = P[]
    last = 1
    for (i,p) in enumerate(points)
        if isnan(p) || i==length(points)
            _i = isnan(p) ? i-1 : i
            handle_segment(lines, line_segments, points, last:_i)
            last = i+1
        end
    end
    if !isempty(lines)
        pop!(lines) # remove last NaN
        push!(result, visualize(lines, Style(:lines), kw_args))
    end
    if !isempty(line_segments)
        push!(result, visualize(line_segments, Style(:linesegment), kw_args))
    end
    return result
end
