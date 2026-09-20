///|
pub struct Session {
  priv scene_gpu : Ref[SceneGpu?]
  priv text_gpu : Ref[TextGpu?]
  priv gpu_frame : Ref[GpuFrame?]
}

///|
pub fn create() -> Session {
  { scene_gpu: Ref(None), text_gpu: Ref(None), gpu_frame: Ref(None), }
}
