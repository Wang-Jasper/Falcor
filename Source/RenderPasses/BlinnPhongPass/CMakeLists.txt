add_plugin(BlinnPhongPass)

target_sources(BlinnPhongPass PRIVATE
    BlinnPhongPass.cpp
    BlinnPhongPass.h
    BlinnPhong.3d.slang
)

target_copy_shaders(BlinnPhongPass RenderPasses/BlinnPhongPass)
target_source_group(BlinnPhongPass "RenderPasses")
