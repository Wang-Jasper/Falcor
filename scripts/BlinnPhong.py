from falcor import *


def render_graph_BlinnPhong():
    g = RenderGraph("BlinnPhong")

    g.addPass(createPass("BlinnPhongPass"), "Lighting")
    g.addPass(
        createPass("ToneMapper", {
            "autoExposure": False,
            "exposureCompensation": 0.0,
        }),
        "ToneMapper",
    )

    g.addEdge("Lighting.color", "ToneMapper.src")
    g.markOutput("ToneMapper.dst")

    return g


g = render_graph_BlinnPhong()

try:
    m.addGraph(g)
except NameError:
    pass
