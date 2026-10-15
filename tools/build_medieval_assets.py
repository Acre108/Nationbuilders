"""Rebuild the original Hearthlands building kit with Blender 3.2+.

Run: blender --background --python tools/build_medieval_assets.py
Game coordinates in helpers are X, height, Z; one unit is one village tile.
Exports are texture-free GLBs, with editable collections in medieval_buildings.blend.
"""
import math
from pathlib import Path
import bpy
import bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets' / 'buildings' / 'medieval'
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
MATS = {}
PARTS = []
ASSETS = []
TIMBER = '54382b'
WOOD = '96704b'
STONE = '898475'
PLASTER = 'ead7af'
CLAY = 'b76240'
IRON = '484b48'


def xyz(p):
    return Vector((p[0], -p[2], p[1]))


def material(color, kind='plain'):
    key = kind + '_' + color
    if key not in MATS:
        mat = bpy.data.materials.new(key)
        rgb = [int(color[i:i+2], 16) / 255 for i in (0, 2, 4)]
        mat.diffuse_color = (*rgb, 1)
        mat.use_nodes = True
        node = mat.node_tree.nodes.get('Principled BSDF')
        node.inputs['Base Color'].default_value = (*rgb, 1)
        node.inputs['Roughness'].default_value = .9
        MATS[key] = mat
    return MATS[key]


def finish(obj, color, kind='plain'):
    obj.data.materials.append(material(color, kind))
    PARTS.append(obj)
    return obj


def box(p, size, color=TIMBER, kind='plain'):
    bpy.ops.mesh.primitive_cube_add(size=1, location=xyz(p))
    obj = bpy.context.object
    obj.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, color, kind)


def cylinder(p, radius, height, color=WOOD, vertices=12, top=None):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius,
        radius2=radius if top is None else top, depth=height, location=xyz(p))
    return finish(bpy.context.object, color)


def beam(a, b, width=.065, color=TIMBER, thickness=None):
    middle = (xyz(a) + xyz(b)) / 2
    direction = xyz(b) - xyz(a)
    bpy.ops.mesh.primitive_cube_add(size=1, location=middle)
    obj = bpy.context.object
    obj.scale = (width, thickness or width, direction.length)
    obj.rotation_euler = direction.to_track_quat('Z', 'Y').to_euler()
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, color)


def mesh(name, vertices, faces, color, kind='plain'):
    data = bpy.data.meshes.new(name)
    data.from_pydata([xyz(v) for v in vertices], [], faces)
    data.update()
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(data)
    bm.free()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    return finish(obj, color, kind)


def ellipsoid(p, size, color):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=5, radius=1, location=xyz(p))
    obj = bpy.context.object
    obj.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, color)


def slab(name, corners, thickness, color, kind='roof'):
    # A sloped roof plate with real thickness, so it renders from every side.
    top = list(corners)
    bottom = [(x, y-thickness, z) for x, y, z in corners]
    return mesh(name, top+bottom, [(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)], color, kind)


def foundation(width, depth, z=-.17):
    box((0, .09, z), (width+.06, .18, depth+.04), '686a5b')
    for course in range(2):
        for i in range(max(3, int(width / .28))):
            n = max(3, int(width / .28))
            x = -width/2 + (i+.5)*width/n
            box((x, .09+course*.105, z+depth/2), (width/n-.014,.085,.10),
                ['898475','a29a83','777866'][(i+course)%3])
        for side in (-1, 1):
            for i in range(max(3, int(depth / .28))):
                n = max(3, int(depth / .28))
                box((side*width/2,.09+course*.105,z-depth/2+(i+.5)*depth/n),
                    (.10,.085,depth/n-.014), ['898475','a29a83','777866'][(i+course)%3])


def roof(width, depth, eave, rise, z=-.17, color=CLAY):
    w, d = width/2, depth/2
    mesh('Roof', [(-w,eave,z-d),(w,eave,z-d),(0,eave+rise,z-d),
        (-w,eave,z+d),(w,eave,z+d),(0,eave+rise,z+d)],
        [(0,2,1),(3,4,5),(0,3,5,2),(1,2,5,4),(0,1,4,3)], color, 'roof')
    for side in (-1, 1):
        beam((side*w,eave,z-d),(side*w,eave,z+d),.075)
        for front in (-1,1):
            beam((side*w,eave-.02,z+front*d),(0,eave+rise+.015,z+front*d),.065)
        # Broad raised roof courses read at the game's native pixel size.
        for row in range(1,5):
            t = row/5
            beam((side*w*(1-t),eave+rise*t+.018,z-d),
                 (side*w*(1-t),eave+rise*t+.018,z+d), .027,
                 'd58954' if color == CLAY else '758c8c', .034)
    beam((0,eave+rise+.025,z-d-.025),(0,eave+rise+.025,z+d+.025),.085,
         'd58954' if color == CLAY else '637b80')


def window(x, y, z, side=False, shutters=True):
    if side:
        box((x,y,z),(.05,.30,.27),'302f2b')
        for dz in (-.17,.17): box((x,y,z+dz),(.07,.39,.065))
        for dy in (-.18,.18): box((x,y+dy,z),(.075,.065,.40))
        box((x+.02,y,z),(.05,.30,.025),'c2a375')
        if shutters:
            for dz in (-.26,.26): box((x,y,z+dz),(.07,.31,.14),'6f8568')
    else:
        box((x,y,z),(.27,.30,.045),'302f2b')
        for dx in (-.17,.17): box((x+dx,y,z+.018),(.065,.39,.07))
        for dy in (-.18,.18): box((x,y+dy,z+.018),(.40,.065,.075))
        box((x,y,z+.043),(.025,.30,.025),'c2a375')
        if shutters:
            for dx in (-.26,.26):
                box((x+dx,y,z+.02),(.14,.31,.07),'6f8568')
                box((x+dx,y-.085,z+.06),(.14,.026,.015),TIMBER)


def door(x, z, height=.69, width=.36):
    for i in range(4):
        box((x-width/2+(i+.5)*width/4,.23+height/2,z), (width/4-.006,height,.055),WOOD,'timber')
    for dx in (-width/2-.025,width/2+.025): box((x+dx,.23+height/2,z+.02),(.055,height+.07,.085))
    box((x,.23+height,z+.02),(width+.13,.065,.09))
    for y in (.37,.73): box((x,y,z+.034),(width,.03,.02),IRON)
    cylinder((x+.10,.52,z+.045),.025,.028,'c6a66d',8)
    box((x,.13,z+.13),(width+.20,.09,.27),'a29a83')


def cottage(width=1.55, depth=1.10, height=1.05, plaster=PLASTER, upper=False):
    z = -.25
    foundation(width,depth,z)
    box((0,.20+height/2,z),(width,height,depth),plaster,'wall')
    front = z+depth/2+.03
    for x in (-width/2,0,width/2):
        for zz in (z-depth/2,front): box((x,.20+height/2,zz),(.075,height+.045,.065))
    for y in (.27,.20+height):
        box((0,y,front),(width+.08,.075,.07))
        for side in (-1,1): box((side*width/2,y,z),(.07,.075,depth))
    for side in (-1,1):
        beam((side*width/2,.36,z-depth/2+.1),(side*width/2,.20+height-.15,z-.08),.055)
    rise = .78 if upper else .67
    roof(width+.22,depth+.28,.20+height,rise,z,'506d75' if upper else CLAY)
    beam((0,.20+height,front+.1),(0,.20+height+rise-.07,front+.1),.065)
    if upper:
        box((0,.94,front),(width,.075,.07))
        for x in (-width/2+.08,width/2-.08):
            beam((x,.99,front),(x*.35,height+.13,front),.05)
    door(-.30,front+.045)
    window(.39, .85 if not upper else 1.13,front+.04)
    window(-width/2-.045,.84,z-.1,side=True)
    return front


def chimney(x=.42,z=-.50,base=1.2,height=1.03):
    box((x,base+height/2,z),(.24,height,.26),'937d69','wall')
    for j in range(5): box((x,base+height*.18*j,z+.135),(.245,.025,.016),'c0a38a')
    box((x,base+height+.045,z),(.32,.09,.34),'67554a')
    box((x,base+height+.094,z),(.17,.012,.19),'343632')


def sign(x,z,good):
    beam((x,1.13,z-.16),(x,1.13,z+.25),.045)
    for dx in (-.10,.10): beam((x+dx,1.13,z+.24),(x+dx,.98,z+.24),.022,IRON)
    box((x,.89,z+.24),(.34,.20,.07),WOOD)
    if good == 'bread':
        ellipsoid((x,.89,z+.29),(.12,.045,.025),'e5b96a')
    elif good == 'fish':
        ellipsoid((x-.02,.89,z+.29),(.11,.045,.02),'a9c1c6')
        mesh('Tail',[(x+.08,.89,z+.29),(x+.15,.95,z+.29),(x+.15,.83,z+.29),
            (x+.08,.89,z+.30),(x+.15,.95,z+.30),(x+.15,.83,z+.30)],
            [(0,1,2),(3,5,4),(0,3,4,1),(1,4,5,2),(2,5,3,0)],'a9c1c6')
    elif good == 'meat':
        ellipsoid((x+.02,.88,z+.29),(.09,.065,.025),'b4574c')
        beam((x-.13,.92,z+.29),(x-.04,.89,z+.29),.03,'efe2c8')
    elif good == 'tree':
        beam((x,.82,z+.285),(x,.95,z+.285),.022,'e0be65')
        ellipsoid((x,.92,z+.29),(.080,.066,.020),'a8bf73')
    else:
        beam((x-.08,.83,z+.285),(x+.08,.95,z+.285),.025,'e0be65')
        beam((x-.07,.95,z+.285),(x+.07,.83,z+.285),.025,'e0be65')


def awning(width,z,y=1.05,color='758564'):
    for i in range(6):
        x=-width/2+(i+.5)*width/6
        part=box((x,y,z),(width/6+.005,.045,.38),color if i%2==0 else 'd8caaa')
        part.rotation_euler.x = -.14
    for x in (-width/2,width/2): beam((x,.16,z+.17),(x,y+.01,z+.17),.05)
    box((0,y-.075,z+.19),(width,.12,.04),color)


def house(upper=False):
    front=cottage(height=1.48 if upper else 1.02,upper=upper)
    chimney(base=1.30 if upper else 1.1,height=1.03)
    if upper:
        for x in (-.63,.53):
            box((x,.70,front+.18),(.35,.11,.19),WOOD)
            for dx in (-.10,0,.10): ellipsoid((x+dx,.80,front+.18),(.07,.09,.07),'82925a')
            ellipsoid((x,.88,front+.20),(.06,.05,.05),'c77d64')
    else:
        box((-.68,.20,front+.22),(.21,.15,.25),'877356')
        ellipsoid((-.68,.33,front+.22),(.16,.12,.13),'768c59')


def bakery():
    front=cottage(width=1.55,depth=1.06,plaster='e6c397')
    chimney(x=.48,z=-.51,base=.75,height=1.57)
    # Stone bake oven projects from the side; its dark mouth is a fixture.
    ellipsoid((.73,.47,-.14),(.24,.34,.34),'a98d71')
    box((.90,.31,.17),(.24,.29,.04),'3d352e')
    for dx in (-.15,.15): box((.90+dx,.31,.21),(.055,.29,.065),'c5ad8b')
    box((.90,.49,.21),(.36,.07,.065),'c5ad8b')
    sign(-.65,front,'bread')
    awning(1.17,.64,.97,'a65d48')
    box((0,.29,.70),(1.18,.10,.29),WOOD)
    for x in (-.50,.50): box((x,.19,.70),(.075,.27,.23))


def woodcutter():
    cottage(width=1.08,depth=1.02,height=.92,plaster='c5b087')
    # Open, empty timber drying shelter; all logs are supplied by inventory.
    for x in (.49,.86):
        for z in (-.70,.16): box((x,.60,z),(.055,1.05,.055))
    roof(.49,1.03,1.10,.21,z=-.26,color='8d7851')
    # Split stump and axe: work tools, not stock.
    cylinder((-.69,.28,.63),.17,.27,'896342',10)
    cylinder((-.69,.422,.63),.158,.012,'c3a077',10)
    beam((-.76,.42,.61),(-.61,.81,.61),.029,WOOD)
    box((-.61,.75,.61),(.19,.12,.032),'788181')
    sign(-.36,.35,'axe')


def forester():
    cottage(width=1.15,depth=.97,height=.94,plaster='d5d0a0')
    # A moss-green nursery porch, fenced planting beds and the worker's spade.
    awning(1.1,.59,.98,'688455')
    for x in (-.64,.64):
        box((x,.15,.67),(.42,.17,.48),'66513c')
        for z in (.51,.73):
            for dx in (-.09,.09):
                beam((x+dx,.23,z),(x+dx,.43,z),.018,'705334')
                ellipsoid((x+dx,.43,z),(.075,.12,.075),'6e934a')
        for z in (.42,.90): box((x,.27,z),(.45,.055,.035),WOOD)
    beam((.80,.18,-.40),(.80,.84,-.32),.032,WOOD)
    box((.80,.19,-.40),(.13,.17,.025),'7f8981')
    sign(-.42,.34,'tree')


def storehouse():
    w,d,z=2.52,1.15,-.27
    foundation(w,d,z)
    box((0,.81,z),(w,1.24,d),'bb986b','wall')
    for x in (-1.23,-.64,0,.64,1.23):
        for zz in (z-d/2,z+d/2+.025): box((x,.83,zz),(.085,1.28,.07))
    for y in (.27,1.39): box((0,y,z+d/2+.04),(w,.075,.085))
    roof(2.78,1.45,1.43,.84,z)
    # Double loading doors with heavy iron straps.
    for x in (-.28,.28):
        door(x,z+d/2+.09,height=.88,width=.46)
        beam((x-.19,.30,z+d/2+.14),(x+.19,1.04,z+d/2+.14),.038)
    window(-.94,.85,z+d/2+.06,shutters=False)
    window(.94,.85,z+d/2+.06,shutters=False)
    box((0,.14,.63),(1.40,.12,.37),'8d795c')
    # Loft hatch and external hoist.
    box((0,1.70,.49),(.38,.39,.06),WOOD)
    beam((0,1.51,.53),(0,1.90,.53),.045)
    beam((0,2.03,.45),(0,2.03,.85),.085)
    beam((0,1.96,.79),(0,1.54,.79),.022,'b7a179')
    awning(2.33,.66,1.25,'758564')


def well():
    # Actual open stone ring, with staggered block joints.
    for course in range(3):
        for i in range(12):
            angle=(i+course*.5)*math.tau/12
            obj=box((math.sin(angle)*.30,.16+course*.12,math.cos(angle)*.30),
                (.17,.105,.13),['898475','a29a83','777866'][(i+course)%3])
            obj.rotation_euler.z = -angle
    cylinder((0,.22,0),.24,.015,'397e85',16)
    for x in (-.36,.36): box((x,.85,0),(.07,1.45,.075))
    beam((-.40,1.07,0),(.40,1.07,0),.085,WOOD)
    beam((.43,1.06,0),(.43,.88,0),.035,IRON)
    beam((.43,.88,0),(.50,.88,0),.045,WOOD)
    beam((0,1.07,0),(0,.47,0),.018,'c3ab7c')
    roof(.94,.72,1.49,.34,z=0)


def farm():
    box((0,.08,0),(2.82,.10,1.82),'625337')
    for x in range(7):
        xx=-1.25+x*.38
        box((xx,.145,-.16),(.20,.025,1.34),'897044')
        for z in range(4):
            zz=-.65+z*.30
            if x<2 and z<2: continue
            beam((xx,.15,zz),(xx,.55,zz),.025,'c49f48')
            for dx in (-.045,.045):
                beam((xx,.28,zz),(xx+dx,.48,zz),.020,'b7a45b')
            ellipsoid((xx,.57,zz),(.045,.12,.045),'e7be5d')
    for z in (-.91,.91):
        for x in (-1.43,-.7,0,.7,1.43): box((x,.36,z),(.055,.48,.055))
        for y in (.26,.48): box((0,y,z),(2.9,.045,.05),WOOD)
    # Field shelter and tools, kept separate from harvested sheaves.
    box((-1.08,.47,-.61),(.55,.66,.47),'b99f75','wall')
    old=len(PARTS)
    roof(.72,.65,.80,.31,z=-.61,color='8d7851')
    for obj in PARTS[old:]: obj.location.x-=1.08
    box((-1.08,.41,-.36),(.24,.49,.035),TIMBER)
    beam((-1.39,.14,-.34),(-1.39,.81,-.45),.022,WOOD)
    box((-1.39,.77,-.45),(.21,.035,.025),IRON)


def mill():
    foundation(1.15,1.04,-.16)
    cylinder((0,1.15,-.18),.57,1.96,'e2d3b5',12,top=.39)
    for y,r in ((.36,.555),(1.32,.46),(2.10,.40)):
        cylinder((0,y,-.18),r+.025,.065,TIMBER,12)
    for x in (-.38,.38): beam((x,.27,-.48),(x*.69,2.13,-.40),.065)
    cylinder((0,2.38,-.18),.62,.53,CLAY,12,top=.07)
    cylinder((0,2.665,-.18),.10,.085,'d58954',12)
    door(-.14,.37,height=.64,width=.32)
    window(-.47,1.15,-.1,side=True,shutters=False)
    # Loading platform and stone grinding disk are fixtures.
    box((.62,.15,.25),(.44,.13,.55),WOOD)
    cylinder((.65,.23,-.53),.21,.09,STONE,16)
    cylinder((.65,.28,-.53),.045,.018,'54534a',8)
    # Sails have their own pivot and remain independently animated in Godot.
    static=list(PARTS)
    PARTS.clear()
    pivot=(0,1.91,.49)
    for arm in range(4):
        angle=arm*math.pi/2+.20
        def at(r,t=0):
            return (math.sin(angle)*r+math.cos(angle)*t,pivot[1]+math.cos(angle)*r-math.sin(angle)*t,pivot[2])
        beam(at(.07),at(1.24),.055,'937851')
        for t in (-.055,.25): beam(at(.40,t),at(1.22,t),.025,TIMBER)
        for k in range(6): beam(at(.42+k*.15,-.055),at(.42+k*.15,.25),.023,WOOD)
        canvas=[at(.45,.025),at(1.20,.025),at(1.20,.22),at(.45,.22)]
        canvas += [(x,y,z-.016) for x,y,z in canvas]
        mesh('Canvas',canvas,[(0,1,2,3),(4,7,6,5),(0,4,5,1),
            (1,5,6,2),(2,6,7,3),(3,7,4,0)],'e8dab0')
    ellipsoid(pivot,(.13,.13,.095),TIMBER)
    sails=join('Sails',pivot)
    PARTS.extend(static)
    return sails


def chapel():
    # A small stone chapel on a 2 x 3 plot: plastered nave, slate roof, a
    # timber bell turret over the door and a lancet window on each side.
    w,d,z=1.30,2.05,-.12
    foundation(w,d,z)
    box((0,.20+.70,z),(w,1.40,d),'e3d8bd','wall')
    front=z+d/2+.03
    for x in (-w/2,w/2):
        for zz in (z-d/2,front): box((x,.90,zz),(.09,1.45,.07),STONE)
    for y in (.27,1.60): box((0,y,front),(w+.08,.075,.07))
    roof(w+.24,d+.30,1.60,.86,z,'506d75')
    door(0,front+.045,height=.82,width=.44)
    # Pointed lancet over the door and along both walls.
    mesh('Lancet',[(-.13,1.02,front+.02),(.13,1.02,front+.02),(0,1.38,front+.02),
        (-.13,1.02,front+.05),(.13,1.02,front+.05),(0,1.38,front+.05)],
        [(0,1,2),(3,5,4),(0,3,4,1),(1,4,5,2),(2,5,3,0)],'2f3338')
    for side in (-1,1):
        for zz in (z-.45,z+.35):
            box((side*(w/2+.02),.95,zz),(.05,.46,.20),'2f3338')
            box((side*(w/2+.035),1.21,zz),(.06,.06,.24),STONE)
    # Bell turret: four posts, a hanging bell and a small spire.
    tz=front-.30
    for x in (-.17,.17):
        for dz in (-.17,.17): box((x,2.66,tz+dz),(.05,.42,.05))
    cylinder((0,2.62,tz),.10,.18,'b08d48',10,top=.05)
    box((0,2.47,tz),(.42,.06,.42),TIMBER)
    cylinder((0,3.12,tz),.27,.52,'506d75',4,top=0)
    beam((0,3.36,tz),(0,3.62,tz),.03,'c6a66d')
    beam((-.08,3.53,tz),(.08,3.53,tz),.025,'c6a66d')
    # Churchyard bench and lantern post.
    box((-.48,.22,front+.35),(.46,.06,.16),WOOD)
    for x in (-.66,-.30): box((x,.15,front+.35),(.05,.14,.12),WOOD)
    beam((.55,.10,front+.30),(.55,.82,front+.30),.04,IRON)
    box((.55,.88,front+.30),(.12,.14,.12),'e9c46a')


def berry_bushes():
    # A fenced patch of berry bushes with a picker's bench and basket.
    box((0,.07,0),(1.82,.08,1.82),'5d5434')
    for i,(x,z) in enumerate(((-.48,-.45),(.42,-.50),(-.05,.02),(-.55,.50),(.50,.42))):
        ellipsoid((x,.36,z),(.32,.30,.30),'4f7340' if i%2 else '5b7d45')
        ellipsoid((x+.06,.50,z-.05),(.20,.18,.20),'6b8c4e')
        for j in range(7):
            angle=j*math.tau/7+i
            ellipsoid((x+math.sin(angle)*.26,.30+(j%3)*.10,z+math.cos(angle)*.25),
                (.045,.045,.045),'b23a4c' if j%2 else '7d2a52')
    for z in (-.88,.88):
        for x in (-.85,0,.85): box((x,.24,z),(.05,.34,.05))
        box((0,.33,z),(1.76,.04,.04),WOOD)
    for x in (-.88,.88):
        for zz in (-.43,.43): box((x,.24,zz),(.05,.34,.05))
        box((x,.33,0),(.04,.04,1.76),WOOD)
    box((.62,.20,.78),(.42,.06,.16),WOOD)
    stock('basket',(.62,.23,.78))


def fisher():
    # A tarred shoreline hut on a 2 x 2 plot, with a net-drying rack, an
    # upturned rowing boat and a gutting bench. Fish stock sits by the door.
    front=cottage(width=1.10,depth=.92,height=.86,plaster='9c9a8a')
    for x in (.34,.86):
        box((x,.50,-.62),(.05,.80,.05))
    beam((.34,.86,-.62),(.86,.86,-.62),.04)
    # Hanging nets: a dark mesh panel with float corks along the top.
    box((.60,.62,-.62),(.48,.42,.015),'4f5a52')
    for i in range(4):
        ellipsoid((.40+i*.13,.83,-.61),(.03,.03,.03),'d6a35c')
    # Upturned boat, keel up, on two chocks.
    for x in (-.80,-.40): box((x,.06,-.62),(.07,.10,.42),WOOD)
    mesh('Hull',[(-1.0,.10,-.80),(-.20,.10,-.80),(-.20,.10,-.44),(-1.0,.10,-.44),
        (-.95,.32,-.62),(-.25,.32,-.62)],[(0,1,5,4),(3,4,5,2),(0,4,3),(1,2,5),(0,3,2,1)],'6d5a42')
    beam((-.95,.33,-.62),(-.25,.33,-.62),.03,TIMBER)
    # Gutting bench beside the door.
    box((.55,.30,front+.24),(.46,.05,.22),WOOD)
    for x in (.36,.74): box((x,.15,front+.24),(.05,.28,.18),WOOD)
    box((.55,.335,front+.24),(.12,.012,.05),'9aa3a3')
    sign(-.62,front,'fish')


def woodshed():
    # An open-fronted lean-to on a 2 x 1 plot: plank back wall, four posts,
    # a shingle roof, a chopping block with an axe and a sawhorse.
    w,d,z=1.82,.72,-.06
    box((0,.05,z),(w+.04,.08,d+.04),'686a5b')
    box((0,.52,z-d/2+.03),(w,.94,.05),'8d6f4a','wall')
    for i in range(7):
        box((-w/2+(i+.5)*w/7,.52,z-d/2+.06),(.012,.94,.012),TIMBER)
    for x in (-w/2+.05,0,w/2-.05):
        for zz in (z-d/2+.03,z+d/2-.04): box((x,.55,zz),(.06,1.0,.06))
    slab('Lean',[(-w/2-.08,1.08,z-d/2-.08),(w/2+.08,1.08,z-d/2-.08),
        (w/2+.08,.86,z+d/2+.14),(-w/2-.08,.86,z+d/2+.14)],.04,'8d7851')
    for i in range(4):
        t=(i+.5)/4
        beam((-w/2-.08,1.09-.22*t,z-d/2-.08+(d+.22)*t),(w/2+.08,1.09-.22*t,z-d/2-.08+(d+.22)*t),.022,'a58b5c',.026)
    beam((-w/2-.08,.87,z+d/2+.12),(w/2+.08,.87,z+d/2+.12),.07)
    cylinder((-.62,.15,z+.10),.15,.24,'896342',10)
    cylinder((-.62,.272,z+.10),.14,.012,'c3a077',10)
    beam((-.70,.28,z+.12),(-.57,.58,z+.14),.026,WOOD)
    box((-.57,.55,z+.14),(.15,.10,.03),'788181')
    for x in (.48,.80):
        beam((x,.04,z-.10),(x,.34,z+.06),.03,WOOD)
        beam((x,.04,z+.20),(x,.34,z+.06),.03,WOOD)
    beam((.40,.34,z+.06),(.88,.34,z+.06),.06,WOOD)


def sawmill():
    # A 3 x 2 saw yard: an open shed over a pit-saw trestle holding a log,
    # a sawyer's cottage at the back and a lumber rack. Planks are stock.
    cottage(width=1.10,depth=.80,height=.88,plaster='c9b38c')
    for obj in PARTS: obj.location.x -= .82
    # Open shed over the saw pit.
    sx,sz=.62,-.10
    for x in (sx-.62,sx+.62):
        for zz in (sz-.58,sz+.58): box((x,.62,zz),(.07,1.16,.07))
    old=len(PARTS)
    roof(1.42,1.36,1.20,.40,z=sz,color='8d7851')
    for obj in PARTS[old:]: obj.location.x += sx
    box((sx,.04,sz),(1.10,.06,.86),'4a3d2c')
    for x in (sx-.42,sx+.42):
        for zz in (sz-.22,sz+.22): beam((x,.04,zz),(x,.52,zz),.05,WOOD)
        beam((x,.52,sz-.25),(x,.52,sz+.25),.06,WOOD)
    beam((sx-.60,.60,sz),(sx+.60,.60,sz),.16,'76543a',.16)
    box((sx+.61,.60,sz),(.012,.13,.13),'cda775')
    # The long two-man saw, standing upright through the log.
    beam((sx+.10,.20,sz),(sx+.10,1.05,sz),.012,'9aa3a3',.10)
    beam((sx+.02,1.05,sz),(sx+.18,1.05,sz),.03,WOOD)
    # Lumber rack along the front.
    for x in (-.30,.30,.90):
        box((x,.30,.72),(.05,.56,.05),WOOD)
    beam((-.34,.56,.72),(.94,.56,.72),.05,WOOD)


def pig_farm():
    # A muddy 3 x 2 sty: wattle fence, a thatched pig shelter, a feeding
    # trough and a farmer's hut. Pigs ready for the butcher are stock.
    box((0,.05,.10),(2.80,.06,1.56),'6b5636')
    for i,(x,z,r) in enumerate(((-.20,.30,.30),(.55,.55,.22),(.20,-.05,.18),(.95,.10,.26))):
        cylinder((x,.083,z),r,.012,'54432c' if i%2 else '5d4a30',12)
    for z in (-.66,.86):
        for x in (-.10,.45,1.0,1.36): box((x,.26,z),(.05,.40,.05),WOOD)
        for y in (.18,.32): box((.63,y,z),(1.48,.06,.035),'8a7350')
    for x in (-.12,1.38):
        for zz in (-.30,.10,.50): box((x,.26,zz),(.05,.40,.05),WOOD)
        for y in (.18,.32): box((x,y,.10),(.035,.06,1.50),'8a7350')
    # Farmer's hut on the west end.
    box((-.88,.48,-.05),(.86,.80,1.0),'b99f75','wall')
    old=len(PARTS)
    roof(1.06,1.20,.88,.40,z=-.05,color='b49650')
    for obj in PARTS[old:]: obj.location.x -= .88
    door(-.88,.47,height=.58,width=.30)
    # Low open shelter inside the pen.
    for x in (.20,.95):
        box((x,.30,-.44),(.05,.46,.05),WOOD)
    slab('Shelter',[(.12,.58,-.66),(1.03,.58,-.66),(1.03,.46,-.22),(.12,.46,-.22)],.04,'b49650')
    # Feeding trough.
    box((.60,.13,.62),(.62,.12,.16),'76543a')
    box((.60,.185,.62),(.54,.02,.10),'c9a85a')


def butcher():
    # A red-washed shop on a 2 x 2 plot, with a striped awning, a counter,
    # hooks with hams and a salting tub. Meat for sale is stock.
    front=cottage(width=1.50,depth=1.02,plaster='d4a58f')
    chimney(x=-.45,z=-.48,base=1.1,height=.9)
    sign(.62,front,'meat')
    awning(1.17,.62,.97,'8c3b38')
    box((0,.29,.66),(1.10,.10,.26),WOOD)
    for x in (-.48,.48): box((x,.19,.66),(.075,.27,.21))
    # Hams hanging under the awning.
    beam((-.50,.86,.70),(.50,.86,.70),.025,IRON)
    for x in (-.32,0,.30):
        beam((x,.86,.70),(x,.74,.70),.012,IRON)
        ellipsoid((x,.66,.70),(.07,.10,.07),'b4574c')
    # Salting tub at the side.
    cylinder((.92,.17,-.05),.17,.32,'8a6a44',12,top=.15)
    for y in (.06,.28): cylinder((.92,y,-.05),.172,.025,IRON,12)
    cylinder((.92,.33,-.05),.14,.012,'eee8de',12)


def hunter():
    # A dark log lodge on a 2 x 2 plot: antlers over the door, a hide on a
    # stretching frame, a game rack and a chopping stump. Meat is stock.
    front=cottage(width=1.20,depth=.98,height=.92,plaster='6e5a44')
    # Log courses across the front wall read as a cabin rather than plaster.
    for i in range(6):
        beam((-.60,.30+i*.14,front-.01),(.60,.30+i*.14,front-.01),.055,'5a4632')
    door(-.30,front+.045,height=.64,width=.34)
    for z in (-.03,.03):
        beam((-.30,1.12,front+.06),(-.30+z*6,1.30,front+.06),.022,'d8c9a8')
        beam((-.30+z*3,1.21,front+.06),(-.30+z*7,1.26,front+.06),.016,'d8c9a8')
    box((-.30,1.10,front+.05),(.10,.07,.05),'8a5a3a')
    # Hide stretched on a frame of poles.
    for x in (.48,.92):
        beam((x,.02,.58),(x,.86,.58),.035,WOOD)
    for y in (.20,.80):
        beam((.46,y,.58),(.94,y,.58),.03,WOOD)
    mesh('Hide',[(.52,.24,.585),(.88,.26,.585),(.86,.76,.585),(.54,.74,.585),
        (.52,.24,.60),(.88,.26,.60),(.86,.76,.60),(.54,.74,.60)],
        [(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],'b8875a')
    # Game rack on the side wall, and the stump with a skinning knife.
    beam((.70,.95,-.70),(.70,.95,.10),.04,WOOD)
    for z in (-.55,-.30):
        beam((.70,.95,z),(.70,.80,z),.012,IRON)
        ellipsoid((.70,.70,z),(.05,.10,.05),'8a5a3a')
    cylinder((-.72,.14,.62),.15,.24,'896342',10)
    cylinder((-.72,.262,.62),.14,.012,'c3a077',10)
    beam((-.75,.27,.58),(-.66,.30,.66),.02,'9aa3a3')


def deer():
    # A red deer stag, head toward +X, about half a tile long. Legs, neck and
    # antlers are thin beams so it reads at village zoom.
    hide, belly = '8a5a3a', 'c9a27a'
    ellipsoid((0,.34,0),(.21,.10,.085),hide)
    ellipsoid((0,.30,0),(.17,.06,.07),belly)
    for x in (-.13,.13):
        for z in (-.045,.045):
            beam((x,.31,z),(x+.01,.02,z),.032,'6e4630')
            box((x+.01,.012,z),(.035,.024,.035),'2f2a24')
    beam((.14,.38,0),(.23,.55,0),.06,hide)
    ellipsoid((.27,.57,0),(.075,.048,.045),hide)
    ellipsoid((.335,.555,0),(.035,.028,.028),'5a3c2a')
    for z in (-.045,.045):
        ellipsoid((.23,.62,z*1.4),(.02,.04,.012),hide)
        beam((.25,.60,z*.8),(.22,.78,z*2.2),.014,'d8c9a8')
        beam((.225,.70,z*1.6),(.28,.76,z*2.0),.011,'d8c9a8')
        beam((.22,.76,z*2.1),(.17,.84,z*2.4),.011,'d8c9a8')
    ellipsoid((-.21,.37,0),(.03,.03,.025),'eee4d0')


def boar():
    # A wild boar, head toward +X: low and heavy, with a bristled ridge, a
    # snout disc and small tusks.
    hide = '4a3b30'
    ellipsoid((0,.20,0),(.20,.115,.10),hide)
    ellipsoid((.03,.25,0),(.14,.09,.08),'5a483a')
    for i in range(5):
        box((-.12+i*.06,.33-abs(i-2)*.012,0),(.05,.035,.03),'2f2620')
    ellipsoid((.20,.18,0),(.09,.07,.065),hide)
    cylinder((.29,.15,0),.035,.03,'8a6a5a',8).rotation_euler.y = math.pi/2
    for z in (-.03,.03):
        beam((.26,.13,z),(.30,.17,z*1.4),.012,'e8e0c8')
        ellipsoid((.17,.25,z*1.6),(.02,.035,.015),hide)
    for x in (-.11,.11):
        for z in (-.05,.05):
            beam((x,.14,z),(x,.02,z),.035,'3a2e26')


def sack(color='d8caaa'):
    cylinder((0,.13,0),.12,.24,color,10,top=.087)
    ellipsoid((0,.07,0),(.126,.075,.12),color)
    cylinder((0,.255,0),.050,.050,color,8,top=.045)
    cylinder((0,.233,0),.066,.023,TIMBER,10)


def basket(p, berries=True):
    x,y,z=p
    cylinder((x,y+.08,z),.13,.16,'a07a46',12,top=.15)
    cylinder((x,y+.165,z),.155,.02,'7a5a33',12)
    for i in range(6):
        angle=i*math.tau/6
        beam((x+math.sin(angle)*.14,y+.02,z+math.cos(angle)*.14),
             (x+math.sin(angle)*.15,y+.16,z+math.cos(angle)*.15),.012,'7a5a33')
    if berries:
        for i in range(9):
            angle=i*math.tau/9
            r=.04+(i%3)*.03
            ellipsoid((x+math.sin(angle)*r,y+.18+(i%2)*.02,z+math.cos(angle)*r),
                (.035,.035,.035),'b23a4c' if i%2 else '7d2a52')


def stock(good, at=(0,0,0)):
    if good in ('berries','basket'):
        basket(at)
    elif good == 'flour':
        sack()
        box((0,.14,.121),(.065,.065,.009),'a98d71')
    elif good == 'water':
        cylinder((0,.145,0),.125,.25,'a78a61',12,top=.105)
        for y in (.045,.23): cylinder((0,y,0),.128,.029,IRON,12)
        cylinder((0,.279,0),.105,.025,'6f674f',12)
        cylinder((.035,.297,0),.022,.015,'cfbb84',8)
    elif good == 'logs':
        for x,y in ((-.075,.085),(.075,.085),(0,.21)):
            beam((x,y,-.16),(x,y,.16),.125,'76543a',thickness=.125)
            box((x,y,.164),(.095,.095,.010),'cda775')
    elif good == 'wheat':
        for i in range(6):
            angle=i*math.tau/6
            x,z=math.sin(angle)*.045,math.cos(angle)*.045
            beam((x*.5,.02,z*.5),(x,.30,z),.024,'c4a14f')
            ellipsoid((x,.31,z),(.028,.071,.03),'efc76b')
        cylinder((0,.15,0),.078,.026,TIMBER,10)
    elif good == 'fish':
        box((0,.025,0),(.32,.04,.22),WOOD)
        for z,color in ((-.05,'a9c1c6'),(.05,'8fb0b8')):
            ellipsoid((-.02,.08,z),(.12,.04,.045),color)
            mesh('Tail',[(.09,.08,z),(.16,.08,z-.045),(.16,.08,z+.045),
                (.09,.10,z),(.16,.10,z-.045),(.16,.10,z+.045)],
                [(0,1,2),(3,5,4),(0,3,4,1),(1,4,5,2),(2,5,3,0)],color)
            ellipsoid((-.10,.095,z+.02),(.012,.012,.012),'262626')
    elif good == 'meat':
        box((0,.025,0),(.30,.04,.24),WOOD)
        ellipsoid((.02,.10,0),(.11,.075,.085),'b4574c')
        ellipsoid((.05,.11,0),(.06,.05,.06),'e8c9b4')
        beam((-.14,.12,0),(-.06,.10,0),.035,'efe2c8')
    elif good == 'pigs':
        ellipsoid((0,.13,0),(.17,.10,.10),'e0a6a0')
        ellipsoid((.16,.15,0),(.07,.065,.065),'e0a6a0')
        cylinder((.225,.15,0),.03,.02,'c98a86',8)
        for x in (-.10,.10):
            for z in (-.05,.05): cylinder((x,.04,z),.025,.08,'c98a86',6)
        for z in (-.035,.035): ellipsoid((.15,.22,z),(.02,.03,.015),'c98a86')
    elif good == 'firewood':
        for i,(x,y) in enumerate(((-.10,.06),(0,.06),(.10,.06),(-.05,.15),(.05,.15),(0,.24))):
            beam((x,y,-.15),(x,y,.15),.085,"94683f",thickness=.085)
            box((x,y,.152),(.06,.06,.006),'d8b27a')
    elif good == 'planks':
        for i in range(4):
            box((0,.025+i*.05,0),(.18,.04,.36),'c9a46b' if i%2 else 'b8925d')
        for z in (-.12,.12): box((0,.12,z),(.20,.012,.025),TIMBER)
    elif good == 'bread':
        box((0,.025,0),(.31,.04,.24),WOOD)
        for x in (-.074,.074):
            ellipsoid((x,.092,0),(.065,.065,.097),'d9a154')
            for z in (-.038,.028): beam((x-.036,.149,z),(x+.036,.149,z+.019),.012,'f3d38d')
    else:
        box((0,.13,0),(.25,.25,.25),WOOD)
        for y in (.055,.22): box((0,y,.135),(.28,.035,.025),TIMBER)
        for x in (-.105,.105): box((x,.13,.14),(.027,.28,.025),TIMBER)


def join(name, pivot=(0,0,0)):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in PARTS: obj.select_set(True)
    bpy.context.view_layer.objects.active=PARTS[0]
    bpy.ops.object.join()
    obj=bpy.context.object
    obj.name=name
    # Animated exports need world-aligned axes, independent of the first beam.
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bpy.context.scene.cursor.location=xyz(pivot)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    PARTS.clear()
    return obj


def export(name, maker):
    PARTS.clear()
    extra=maker()
    body=join('Body')
    objects=[body]+([extra] if extra else [])
    collection=bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(collection)
    for obj in objects:
        for parent in list(obj.users_collection): parent.objects.unlink(obj)
        collection.objects.link(obj)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects: obj.select_set(True)
    bpy.context.view_layer.objects.active=body
    bpy.ops.export_scene.gltf(filepath=str(OUT / (name+'.glb')),export_format='GLB',
        use_selection=True,export_texcoords=False,export_normals=True,export_materials='EXPORT')
    ASSETS.append((name,objects))
    print('EXPORTED',name, sum(len(o.data.polygons) for o in objects),'faces')


import sys
# Optional names after "--" export only those assets and leave the .blend alone:
#   blender --background --python tools/build_medieval_assets.py -- chapel stock_berries
ONLY = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
for name, maker in [('house',house),('house_tier2',lambda:house(True)),('storehouse',storehouse),
        ('farm',farm),('well',well),('woodcutter',woodcutter),('forester',forester),('mill',mill),('bakery',bakery),
        ('chapel',chapel),('berry_bushes',berry_bushes),('fisher',fisher),('woodshed',woodshed),
        ('sawmill',sawmill),('pig_farm',pig_farm),('butcher',butcher),('hunter',hunter)]:
    if not ONLY or name in ONLY: export(name,maker)
for good in ('wheat','flour','water','logs','bread','berries','fish','meat','pigs','firewood','planks','crate'):
    if not ONLY or 'stock_'+good in ONLY: export('stock_'+good,lambda good=good:stock(good))
# Game animals (docs/WILDLIFE.md), drawn by view/village_wildlife.gd.
for name, maker in [('animal_deer',deer),('animal_boar',boar)]:
    if not ONLY or name in ONLY: export(name,maker)
if ONLY: sys.exit(0)

# Arrange the source kit as a browsable gallery; exported assets retain origin pivots.
for i,(name,objects) in enumerate(ASSETS):
    for obj in objects:
        obj.location += Vector(((i%4)*4.2, -(i//4)*4.2, 0))
bpy.context.scene.cursor.location=(0,0,0)
bpy.ops.object.select_all(action='DESELECT')
source=OUT / 'source'
source.mkdir(exist_ok=True)
(source / '.gdignore').write_text('# Editable Blender source; runtime uses the exported GLBs.\n')
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(source / 'medieval_buildings.blend'))
print('Medieval kit complete:',len(ASSETS),'GLBs')
