add_plugin(PBRLightingPass)

target_sources(PBRLightingPass PRIVATE
    PBRLightingPass.cpp
    PBRLightingPass.h
    PBRLightingPass.ps.slang
)

target_copy_shaders(PBRLightingPass RenderPasses/PBRLightingPass)

target_source_group(PBRLightingPass "RenderPasses")
