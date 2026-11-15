from falcor import *


def render_graph_PBR():
    g = RenderGraph("PBR")

    g.addPass(createPass("GBufferRaster"), "GBuffer")
    g.addPass(createPass("PBRLightingPass"), "Lighting")
    g.addPass(
        createPass("ToneMapper", {
            "autoExposure": False,
            "exposureCompensation": 0.0,
        }),
        "ToneMapper",
    )

    g.addEdge("GBuffer.posW", "Lighting.posW")
    g.addEdge("GBuffer.guideNormalW", "Lighting.normW")
    g.addEdge("GBuffer.diffuseOpacity", "Lighting.diffuseOpacity")
    g.addEdge("GBuffer.specRough", "Lighting.specRough")
    g.addEdge("GBuffer.emissive", "Lighting.emissive")
    g.addEdge("Lighting.color", "ToneMapper.src")
    g.markOutput("ToneMapper.dst")

    return g


g = render_graph_PBR()

try:
    m.addGraph(g)
except NameError:
    pass
