program PasGLTFViewer;
{$ifdef fpc}
 {$mode delphi}
{$endif}
{-$apptype console}
{$ifdef win32}
 {$define windows}
{$endif}
{$ifdef win64}
 {$define windows}
{$endif}

//  FastMM4,

uses
  SysUtils,
  Classes,
  Math,
  dglOpenGL in 'dglOpenGL.pas',
  UnitSDL2 in 'UnitSDL2.pas',
  UnitStaticLinking in 'UnitStaticLinking.pas',
  PasDblStrUtils in '..\..\externals\pasdblstrutils\src\PasDblStrUtils.pas',
  PasJSON in '..\..\externals\pasjson\src\PasJSON.pas',
  PasGLTF in '..\PasGLTF.pas',
  UnitGLTFOpenGL in 'UnitGLTFOpenGL.pas',
  UnitOpenGLImage in 'UnitOpenGLImage.pas',
  UnitOpenGLImageJPEG in 'UnitOpenGLImageJPEG.pas',
  UnitOpenGLImagePNG in 'UnitOpenGLImagePNG.pas',
  UnitMath3D in 'UnitMath3D.pas',
  UnitOpenGLShader in 'UnitOpenGLShader.pas',
  UnitOpenGLShadingShader in 'UnitOpenGLShadingShader.pas',
  UnitOpenGLFrameBufferObject in 'UnitOpenGLFrameBufferObject.pas',
  UnitOpenGLBRDFLUTShader in 'UnitOpenGLBRDFLUTShader.pas',
  UnitOpenGLEnvMapFilterShader in 'UnitOpenGLEnvMapFilterShader.pas',
  UnitOpenGLEnvMapDrawShader in 'UnitOpenGLEnvMapDrawShader.pas',
  UnitOpenGLAntialiasingShader in 'UnitOpenGLAntialiasingShader.pas',
  UnitOpenGLHDRToLDRShader in 'UnitOpenGLHDRToLDRShader.pas',
  UnitOpenGLEnvMapGenShader in 'UnitOpenGLEnvMapGenShader.pas',
  UnitFontPNG in 'UnitFontPNG.pas',
  UnitOpenGLSpriteBatch in 'UnitOpenGLSpriteBatch.pas',
  UnitOpenGLExtendedBlitRectShader in 'UnitOpenGLExtendedBlitRectShader.pas',
  UnitConsole in 'UnitConsole.pas';

const Title='PasGLTF viewer';

      Version='2018.08.26.16.00.0000';

      Copyright='Copyright (C) 2018, Benjamin ''BeRo'' Rosseaux';

// Force usage of dedicated GPU for OpenGL with Delphi and FreePascal/Lazarus on Multi-GPU systems such as Notebooks on Windows
// Insert that into your main source file, which is for example the .dpr (Delphi) or .lpr (Lazarus) file

//{$define ForceDedicatedGPUUsage} // then you can uncomment and recomment this line, for compile-time-switching between
                                   // integrated GPU and dedicated GPU

{$if defined(Windows) and defined(ForceDedicatedGPUUsage) and (defined(cpu386) or defined(cpux64) or defined(cpuamd64))}
{$ifdef fpc}
 {$asmmode intel}
{$endif}
procedure NvOptimusEnablement; {$ifdef fpc}assembler; nostackframe;{$endif}
asm
{$ifdef cpu64}
{$ifndef fpc}
 .NOFRAME
{$endif}
{$endif}
 dd 1
end;

procedure AmdPowerXpressRequestHighPerformance; {$ifdef fpc}assembler; nostackframe;{$endif}
asm
{$ifdef cpu64}
{$ifndef fpc}
 .NOFRAME
{$endif}
{$endif}
 dd 1
end;

exports NvOptimusEnablement,
        AmdPowerXpressRequestHighPerformance;
{$ifend}

const VirtualCanvasWidth=1280;
      VirtualCanvasHeight=720;

var InputFileName:TPasGLTFUTF8String='';

    CurrentFileName:TPasGLTFUTF8String='';

    StartPerformanceCounter:Int64=0;

    GLTFOpenGL:TGLTFOpenGL=nil;

    ShadingShaders:array[boolean,boolean] of TShadingShader;

    BRDFLUTShader:TBRDFLUTShader;

    BRDFLUTFBO:TFBO;

    EnvMapGenShader:TEnvMapGenShader;

    EnvMapFilterShader:TEnvMapFilterShader;

    EnvMapFBO:TFBO;

    EnvMapDrawShader:TEnvMapDrawShader;

    HDRSceneFBO:TFBO;

    HDRToLDRShader:THDRToLDRShader;

    LDRSceneFBO:TFBO;

    AntialiasingShader:TAntialiasingShader;

    EmptyVertexArrayObjectHandle:glUInt;

    EnvMapTextureHandle:glUInt=0;

    SceneFBOWidth:Int32=1280;
    SceneFBOHeight:Int32=720;

    Fullscreen:boolean=false;

    WrapCursor:boolean=false;

    FirstTime:boolean=true;

    AutomaticRotate:boolean=false;

    ButtonLeftPressed:boolean=false;

    AnimationIndex:int32=0;

    ZoomLevel:TPasGLTFFloat=1.0;

    CameraRotationX:TPasGLTFFloat=0.0;
    CameraRotationY:TPasGLTFFloat=0.0;

    FileName:TPasGLTFUTF8String='';

const CubeMapFileNames:array[0..5] of string=
       (
        'posx',
        'negx',
        'posy',
        'negy',
        'posz',
        'negz'
       );

procedure ResetCamera;
begin
 ZoomLevel:=1.0;
 CameraRotationX:=0.0;
 CameraRotationY:=0.0;
end;

function Matrix4x4ProjectionReversedZ(const aFOV,aAspectRatio,aZNear:single):TMatrix4x4;
var f:single;
begin
 f:=1.0/tan(aFOV*DEG2RAD*0.5);
 result[0,0]:=f/aAspectRatio;
 result[0,1]:=0.0;
 result[0,2]:=0.0;
 result[0,3]:=0.0;
 result[1,0]:=0.0;
 result[1,1]:=f;
 result[1,2]:=0.0;
 result[1,3]:=0.0;
 result[2,0]:=0.0;
 result[2,1]:=0.0;
 result[2,2]:=0.0;
 result[2,3]:=-1.0;
 result[3,0]:=0.0;
 result[3,1]:=0.0;
 result[3,2]:=aZNear;
 result[3,3]:=0.0;
end;

var Event:TSDL_Event;
    SurfaceWindow:PSDL_Window;
    SurfaceContext:PSDL_GLContext;
    SDLDisplayMode:TSDL_DisplayMode;
    VideoFlags:longword;
    SDLWaveFormat:TSDL_AudioSpec;
    BufPosition:integer;
    ScreenWidth,ScreenHeight,BestWidth,BestHeight,ViewPortWidth,ViewPortHeight,ViewPortX,ViewPortY:int32;
    ShowCursor:boolean;
    SDLRunning,OldShowCursor:boolean;
    Time,LastTime,DeltaTime:double;
    AnimationTime:double=0.0;

procedure Draw;
var ModelMatrix,
    ViewMatrix,
    ProjectionMatrix,
    SkyBoxViewProjectionMatrix:UnitMath3D.TMatrix4x4;
    LightDirection,Bounds,Center:UnitMath3D.TVector3;
    t:double;
    v,Zoom:TPasGLTFFloat;
    ShadingShader:TShadingShader;
    t0,t1:int64;
begin
 begin
  glBindFrameBuffer(GL_FRAMEBUFFER,HDRSceneFBO.FBOs[0]);
  glDrawBuffer(GL_COLOR_ATTACHMENT0);
  glViewport(0,0,HDRSceneFBO.Width,HDRSceneFBO.Height);
  glClearColor(0.0,0.0,0.0,0.0);
  glClearDepth(0.0);
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);
  ModelMatrix:=Matrix4x4Identity;
  t:=Time*0.125;
  if assigned(GLTFOpenGL) then begin
   Center.x:=(GLTFOpenGL.StaticBoundingBox.Min[0]+GLTFOpenGL.StaticBoundingBox.Max[0])*0.5;
   Center.y:=(GLTFOpenGL.StaticBoundingBox.Min[1]+GLTFOpenGL.StaticBoundingBox.Max[1])*0.5;
   Center.z:=(GLTFOpenGL.StaticBoundingBox.Min[2]+GLTFOpenGL.StaticBoundingBox.Max[2])*0.5;
   Bounds.x:=(GLTFOpenGL.StaticBoundingBox.Max[0]-GLTFOpenGL.StaticBoundingBox.Min[0])*0.5;
   Bounds.y:=(GLTFOpenGL.StaticBoundingBox.Max[1]-GLTFOpenGL.StaticBoundingBox.Min[1])*0.5;
   Bounds.z:=(GLTFOpenGL.StaticBoundingBox.Max[2]-GLTFOpenGL.StaticBoundingBox.Min[2])*0.5;
  end else begin
   Center.x:=0.0;
   Center.y:=0.0;
   Center.z:=0.0;
   Bounds.x:=1.0;
   Bounds.y:=1.0;
   Bounds.z:=1.0;
  end;
  Zoom:=ZoomLevel;
  ViewMatrix:=Matrix4x4LookAt(Vector3Add(Center,
                                         Vector3ScalarMul(Vector3Norm(Vector3(sin(CameraRotationX*PI*2.0)*cos(-CameraRotationY*PI*2.0),
                                                                              sin(-CameraRotationY*PI*2.0),
                                                                              cos(CameraRotationX*PI*2.0)*cos(-CameraRotationY*PI*2.0))),
                                                          Max(Max(Bounds.x,Bounds.y),Bounds.z)*3.0*Zoom)),
                               Center,
                               Vector3YAxis);
{  ViewMatrix:=Matrix4x4LookAt(Vector3Add(Center,
                                         Vector3TermMatrixMul(Vector3(0.0,
                                                                      0.0,
                                                                      Max(Max(Bounds.x,Bounds.y),Bounds.z)*3.0*Zoom),
                                                              Matrix4x4TermMul(Matrix4x4RotateY(CameraRotationX*PI*2.0),
                                                                               Matrix4x4RotateX(CameraRotationY*PI*2.0)))),
                               Center,
                               Vector3YAxis);}
  ProjectionMatrix:=Matrix4x4ProjectionReversedZ(45.0,ViewPortWidth/ViewPortHeight,1e-3);
  glClipControl(GL_LOWER_LEFT,GL_ZERO_TO_ONE);
  glDepthFunc(GL_GEQUAL);
  LightDirection:=Vector3Norm(Vector3(0.5,-1.0,-1.0));
  SkyBoxViewProjectionMatrix:=Matrix4x4TermMul(Matrix4x4Rotation(ViewMatrix),ProjectionMatrix);
  begin
   glDisable(GL_DEPTH_TEST);
   glDisable(GL_CULL_FACE);
   glActiveTexture(GL_TEXTURE0);
   glBindTexture(GL_TEXTURE_2D,EnvMapTextureHandle);
   EnvMapDrawShader.Bind;
   glUniform1i(EnvMapDrawShader.uTexture,0);
   glUniformMatrix4fv(EnvMapDrawShader.uViewProjectionMatrix,1,false,@SkyBoxViewProjectionMatrix);
   glBindVertexArray(EmptyVertexArrayObjectHandle);
   glDrawArrays(GL_TRIANGLES,0,36);
   glBindVertexArray(0);
   EnvMapDrawShader.Unbind;
  end;
  begin
   glActiveTexture(GL_TEXTURE5);
   glBindTexture(GL_TEXTURE_2D,BRDFLUTFBO.TextureHandles[0]);
   glActiveTexture(GL_TEXTURE6);
   glBindTexture(GL_TEXTURE_CUBE_MAP,EnvMapFBO.TextureHandles[0]);
   glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR_MIPMAP_LINEAR);
   glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
   glActiveTexture(GL_TEXTURE0);
   glEnable(GL_DEPTH_TEST);
   glEnable(GL_CULL_FACE);
   glCullFace(GL_BACK);
   for ShadingShader in ShadingShaders do begin
    ShadingShader.Bind;
    glUniform3fv(ShadingShader.uLightDirection,1,@LightDirection);
    glUniform1i(ShadingShader.uEnvMapMaxLevel,Min(EnvMapFBO.WorkMaxLevel,16));
    ShadingShader.Unbind;
   end;
   t0:=SDL_GetPerformanceCounter;
   if assigned(GLTFOpenGL) then begin
    GLTFOpenGL.Draw(TPasGLTF.TMatrix4x4(Pointer(@ModelMatrix)^),
                    TPasGLTF.TMatrix4x4(Pointer(@ViewMatrix)^),
                    TPasGLTF.TMatrix4x4(Pointer(@ProjectionMatrix)^),
                    ShadingShaders[false,false],
                    ShadingShaders[false,true],
                    ShadingShaders[true,false],
                    ShadingShaders[true,true],
                    AnimationIndex,
                    AnimationTime);
   end;
   t1:=SDL_GetPerformanceCounter;
//  write(#13,(t1-t0)/SDL_GetPerformanceFrequency:1:5);
  end;
  glClipControl(GL_LOWER_LEFT,GL_NEGATIVE_ONE_TO_ONE);
 end;
 begin
  glBindFrameBuffer(GL_FRAMEBUFFER,LDRSceneFBO.FBOs[0]);
  glDrawBuffer(GL_COLOR_ATTACHMENT0);
  glViewport(0,0,LDRSceneFBO.Width,LDRSceneFBO.Height);
  glClearColor(0.0,0.0,0.0,0.0);
  glClear(GL_COLOR_BUFFER_BIT);
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_CULL_FACE);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D,HDRSceneFBO.TextureHandles[0]);
  HDRToLDRShader.Bind;
  glUniform1i(HDRToLDRShader.uTexture,0);
  glBindVertexArray(EmptyVertexArrayObjectHandle);
  glDrawArrays(GL_TRIANGLES,0,3);
  glBindVertexArray(0);
  HDRToLDRShader.Unbind;
 end;
 begin
  glBindFrameBuffer(GL_FRAMEBUFFER,0);
  glViewport(0,0,ViewPortWidth,ViewPortHeight);
  glClearColor(0.0,0.0,0.0,0.0);
  glClearDepth(1.0);
  glViewport(ViewPortX,ViewPortY,ViewPortWidth,ViewPortHeight);
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_CULL_FACE);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D,LDRSceneFBO.TextureHandles[0]);
  AntialiasingShader.Bind;
  glUniform1i(AntialiasingShader.uTexture,0);
  glBindVertexArray(EmptyVertexArrayObjectHandle);
  glDrawArrays(GL_TRIANGLES,0,3);
  glBindVertexArray(0);
  AntialiasingShader.Unbind;
  glDisable(GL_BLEND);
  ConsoleInstance.Draw(DeltaTime,ViewPortX,ViewPortY,ViewPortWidth,ViewPortHeight);
  glEnable(GL_DEPTH_TEST);
 end;
end;

procedure Resize(NewWidth,NewHeight:longint);
var Factor:int64;
    rw,rh:longint;
begin
 ScreenWidth:=NewWidth;
 ScreenHeight:=NewHeight;
 if true then begin
  ViewPortX:=0;
  ViewPortY:=0;
  ViewPortWidth:=ScreenWidth;
  ViewPortHeight:=ScreenHeight;
 end else begin
  Factor:=int64($100000000);
  rw:=VirtualCanvasWidth;
  rh:=VirtualCanvasHeight;
  while (max(rw,rh)>=128) and (((rw or rh)<>0) and (((rw or rh) and 1)=0)) do begin
   rw:=rw shr 1;
   rh:=rh shr 1;
  end;
  if ScreenWidth<ScreenHeight then begin
   ViewPortWidth:=((ScreenHeight*rw)+((rh+1) div 2)) div rh;
   ViewPortHeight:=ScreenHeight;
   if ViewPortWidth>ScreenWidth then begin
    Factor:=((ScreenWidth*int64($100000000))+(ViewPortWidth div 2)) div ViewPortWidth;
   end;
  end else begin
   ViewPortWidth:=ScreenWidth;
   ViewPortHeight:=((ScreenWidth*rh)+((rw+1) div 2)) div rw;
   if ViewPortHeight>ScreenHeight then begin
    Factor:=((ScreenHeight*int64($100000000))+(ViewPortHeight div 2)) div ViewPortHeight;
   end;
  end;
  if Factor<int64($100000000) then begin
   ViewPortWidth:=((ViewPortWidth*Factor)+int64($80000000)) div int64($100000000);
   ViewPortHeight:=((ViewPortHeight*Factor)+int64($80000000)) div int64($100000000);
  end;
  if ViewPortWidth<rw then begin
   ViewPortWidth:=rw;
  end;
  if ViewPortHeight<rh then begin
   ViewPortHeight:=rh;
  end;
  ViewPortX:=((ScreenWidth-ViewPortWidth)+1) div 2;
  ViewPortY:=((ScreenHeight-ViewPortHeight)+1) div 2;
 end;
end;

procedure UpdateTitle;
var s:TPasGLTFUTF8String;
begin
 s:=Title+' - Version '+Version+' - '+Copyright;
 if length(CurrentFileName)>0 then begin
  s:=s+' - '+ExtractFileName(CurrentFileName);
  if assigned(GLTFOpenGL) then begin
   s:=s+' - Animation: '+IntToStr(AnimationIndex+1)+' / '+IntToStr(length(GLTFOpenGL.Animations));
   begin
    s:=s+' - Automatic rotation: ';
    if AutomaticRotate then begin
     s:=s+' on';
    end else begin
     s:=s+' off';
    end;
   end;
   begin
    s:=s+' - ';
    if Fullscreen then begin
     s:=s+' Fullscreen';
    end else begin
     s:=s+' Window mode';
    end;
   end;
   begin
    s:=s+' - Mouse action: ';
    if ButtonLeftPressed then begin
     s:=s+' Rotate and zoom';
    end else begin
     s:=s+' None';
    end;
   end;
  end;
 end;
 SDL_SetWindowTitle(SurfaceWindow,PAnsiChar(s));
end;

procedure MainLoop;
var RootPath,TextureFileName:string;
    s:ansistring;
    TempScale:TPasGLTFFloat;
begin
 SDLRunning:=true;
 while SDLRunning do begin

  while SDL_PollEvent(@Event)<>0 do begin
   case Event.type_ of
    SDL_QUITEV,SDL_APP_TERMINATING:begin
     SDLRunning:=false;
     break;
    end;
    SDL_APP_WILLENTERBACKGROUND:begin
     //SDL_PauseAudio(1);
    end;
    SDL_APP_DIDENTERFOREGROUND:begin
     //SDL_PauseAudio(0);
    end;
    SDL_RENDER_TARGETS_RESET,SDL_RENDER_DEVICE_RESET:begin
    end;
    SDL_KEYDOWN:begin
     if ConsoleInstance.Focus then begin
      case Event.key.keysym.sym of
       SDLK_LEFT:begin
        ConsoleInstance.KeyLeft;
       end;
       SDLK_RIGHT:begin
        ConsoleInstance.KeyRight;
       end;
       SDLK_UP:begin
        ConsoleInstance.KeyUp;
       end;
       SDLK_DOWN:begin
        ConsoleInstance.KeyDown;
       end;
       SDLK_BACKSPACE:begin
        ConsoleInstance.KeyBackspace;
       end;
       SDLK_DELETE:begin
        ConsoleInstance.KeyDelete;
       end;
       SDLK_HOME:begin
        ConsoleInstance.KeyBegin;
       end;
       SDLK_END:begin
        ConsoleInstance.KeyEnd;
       end;
      end;
     end else begin
      case Event.key.keysym.sym of
       SDLK_B:begin
        dec(AnimationIndex);
        if (AnimationIndex<-1) and assigned(GLTFOpenGL) then begin
         AnimationIndex:=length(GLTFOpenGL.Animations)-1;
        end;
        AnimationTime:=0.0;
        UpdateTitle;
       end;
       SDLK_N:begin
        inc(AnimationIndex);
        if assigned(GLTFOpenGL) and (AnimationIndex>=length(GLTFOpenGL.Animations)) then begin
         AnimationIndex:=-1;
        end;
        AnimationTime:=0.0;
        UpdateTitle;
       end;
       SDLK_T:begin
        AnimationTime:=0.0;
        UpdateTitle;
       end;
       SDLK_M:begin
        WrapCursor:=not WrapCursor;
        SDL_SetRelativeMouseMode(ord(WrapCursor or FullScreen) and 1);
        UpdateTitle;
       end;
       SDLK_R:begin
        ResetCamera;
        UpdateTitle;
       end;
      end;
     end;
     case Event.key.keysym.sym of
      SDLK_ESCAPE:begin
//     BackKey;
       if ConsoleInstance.Focus then begin
        ConsoleInstance.KeyEscape;
       end else begin
        SDLRunning:=false;
        break;
       end;
      end;
      SDLK_F8,SDLK_CARET,SDLK_BACKQUOTE:begin
       ConsoleInstance.Focus:=not ConsoleInstance.Focus;
      end;
      SDLK_SPACE:begin
       AutomaticRotate:=not AutomaticRotate;
       UpdateTitle;
      end;
      SDLK_RETURN:begin
       if (Event.key.keysym.modifier and ((KMOD_LALT or KMOD_RALT) or (KMOD_LMETA or KMOD_RMETA)))<>0 then begin
        FullScreen:=not FullScreen;
        if FullScreen then begin
         SDL_SetWindowFullscreen(SurfaceWindow,SDL_WINDOW_FULLSCREEN_DESKTOP);
        end else begin
         SDL_SetWindowFullscreen(SurfaceWindow,0);
        end;
        SDL_ShowCursor(ord(not FullScreen) and 1);
        SDL_SetRelativeMouseMode(ord(WrapCursor or FullScreen) and 1);
       end else if ConsoleInstance.Focus then begin
        ConsoleInstance.KeyEnter;
       end;
       UpdateTitle;
      end;
      SDLK_F4:begin
       if (Event.key.keysym.modifier and ((KMOD_LALT or KMOD_RALT) or (KMOD_LMETA or KMOD_RMETA)))<>0 then begin
        SDLRunning:=false;
        break;
       end;
      end;
     end;
    end;
    SDL_KEYUP:begin
    end;
    SDL_TEXTINPUT:begin
     if ConsoleInstance.Focus then begin
      if (Event.tedit.text[0] in ([$20..$7f]-[ord('^'),ord('`')])) and (Event.tedit.text[1]=0) then begin
       ConsoleInstance.KeyChar(ansichar(byte(Event.tedit.text[0] and $ff)));
      end;
     end;
    end;
    SDL_DROPFILE:begin
     if assigned(Event.drop.FileName) then begin
      try
       InputFileName:=Event.drop.FileName;
      finally
       SDL_free(Event.drop.FileName);
      end;
     end;
    end;
    SDL_WINDOWEVENT:begin
     case event.window.event of
      SDL_WINDOWEVENT_RESIZED:begin
       ScreenWidth:=event.window.Data1;
       ScreenHeight:=event.window.Data2;
       Resize(ScreenWidth,ScreenHeight);
      end;
     end;
    end;
    SDL_MOUSEMOTION:begin
     if ButtonLeftPressed then begin
      if (event.motion.xrel<>0) or (event.motion.yrel<>0) then begin
       CameraRotationX:=frac(CameraRotationX+(1.0-(event.motion.xrel*(1.0/ScreenWidth))));
       CameraRotationY:=frac(CameraRotationY+(1.0-(event.motion.yrel*(1.0/ScreenHeight))));
      end;
     end;
    end;
    SDL_MOUSEWHEEL:begin
     ZoomLevel:=Max(1e-4,ZoomLevel+((event.wheel.x+event.wheel.y)*0.1));
    end;
    SDL_MOUSEBUTTONDOWN:begin
     case event.button.button of
      SDL_BUTTON_LEFT:begin
       ButtonLeftPressed:=true;
       UpdateTitle;
      end;
      SDL_BUTTON_RIGHT:begin
      end;
     end;
    end;
    SDL_MOUSEBUTTONUP:begin
     case event.button.button of
      SDL_BUTTON_LEFT:begin
       ButtonLeftPressed:=false;
       UpdateTitle;
      end;
      SDL_BUTTON_RIGHT:begin
      end;
     end;
    end;
   end;
  end;

  Time:=(SDL_GetPerformanceCounter-StartPerformanceCounter)/SDL_GetPerformanceFrequency;

  if FirstTime then begin
   FirstTime:=false;
   DeltaTime:=0.0;
  end else begin
   DeltaTime:=Min(Max(Time-LastTime,0.0),1.0);
  end;

  LastTime:=Time;

  begin
   // 1 1/3 % (quadratically total-pixel-count-wise) super-sampling on top on FXAA
   TempScale:=sqrt(1.33333333);
   SceneFBOWidth:=round(ViewPortWidth*TempScale);
   SceneFBOHeight:=round(ViewPortHeight*TempScale);
   if (HDRSceneFBO.Width<>SceneFBOWidth) or
      (HDRSceneFBO.Height<>SceneFBOHeight) then begin
    DestroyFrameBuffer(HDRSceneFBO);
    HDRSceneFBO.Width:=SceneFBOWidth;
    HDRSceneFBO.Height:=SceneFBOHeight;
    CreateFrameBuffer(HDRSceneFBO);
   end;
   if (LDRSceneFBO.Width<>SceneFBOWidth) or
      (LDRSceneFBO.Height<>SceneFBOHeight) then begin
    DestroyFrameBuffer(LDRSceneFBO);
    LDRSceneFBO.Width:=SceneFBOWidth;
    LDRSceneFBO.Height:=SceneFBOHeight;
    CreateFrameBuffer(LDRSceneFBO);
   end;
  end;
  if AutomaticRotate then begin
   CameraRotationX:=frac(CameraRotationX+(1.0-(DeltaTime*0.1)));
//                 CameraRotationY:=frac(CameraRotationY+(1.0-(DeltaTime*0.015625)));
  end;

  Draw;

  SDL_GL_SwapWindow(SurfaceWindow);

  AnimationTime:=AnimationTime+DeltaTime;

  if length(InputFileName)>0 then begin
   try
    if assigned(GLTFOpenGL) then begin
     GLTFOpenGL.Unload;
     FreeAndNil(GLTFOpenGL);
    end;
    FileName:=ExpandFileName(InputFileName);
    try
     GLTFOpenGL:=TGLTFOpenGL.Create;
     GLTFOpenGL.RootPath:=IncludeTrailingPathDelimiter(ExtractFilePath(FileName));
     GLTFOpenGL.LoadFromFile(FileName);
     GLTFOpenGL.Upload;
     CurrentFileName:=FileName;
    except
     on e:EPasGLTF do begin
      s:=E.ClassName+': '+E.Message;
      SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR or
                               SDL_MESSAGEBOX_BUTTON_RETURNKEY_DEFAULT,
                               PAnsiChar('Exception'),
                               PAnsiChar(s),
                               SurfaceWindow);
      GLTFOpenGL.Unload;
      FreeAndNil(GLTFOpenGL);
      CurrentFileName:='';
     end;
     on e:Exception do begin
      s:=E.ClassName+': '+E.Message;
      SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR or
                               SDL_MESSAGEBOX_BUTTON_RETURNKEY_DEFAULT,
                               PAnsiChar('Exception'),
                               PAnsiChar(s),
                               SurfaceWindow);
      GLTFOpenGL.Unload;
      FreeAndNil(GLTFOpenGL);
      CurrentFileName:='';
      raise;
     end;
    end;
    ResetCamera;
    AnimationIndex:=0;
    AnimationTime:=0.0;
    UpdateTitle;
   finally
    InputFileName:='';
   end;
  end;

 end;
end;

var Index,MultiSampleCounter,DepthBufferSizeCounter,Temp:int32;
    MemoryStream:TMemoryStream;
    ImageData:TPasGLTFPointer;
    ImageWidth,ImageHeight:TPasGLTFInt32;
    OK:boolean;
    Major,Minor:glInt;
    RootPath,TextureFileName:string;
begin

if ParamCount>0 then begin
 InputFileName:=TPasGLTFUTF8String(ParamStr(1));
end;

if SDL_Init(SDL_INIT_EVERYTHING)<0 then begin
 exit;
end;

ScreenWidth:=1280;
ScreenHeight:=720;

if SDL_GetCurrentDisplayMode(0,@SDLDisplayMode)=0 then begin
 BestWidth:=SDLDisplayMode.w;
 BestHeight:=SDLDisplayMode.h;
end else begin
 BestWidth:=640;
 BestHeight:=360;
end;

if ScreenWidth>=((BestWidth*90) div 100) then begin
 Temp:=((BestWidth*90) div 100);
 ScreenHeight:=(ScreenHeight*Temp) div ScreenWidth;
 ScreenWidth:=Temp;
end;
if ScreenHeight>=((BestHeight*90) div 100) then begin
 Temp:=((BestHeight*90) div 100);
 ScreenWidth:=(ScreenWidth*Temp) div ScreenHeight;
 ScreenHeight:=Temp;
end;

SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION,4);
SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION,1);
SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK,SDL_GL_CONTEXT_PROFILE_CORE);
SDL_GL_SetAttribute(SDL_GL_CONTEXT_FLAGS,0);
SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS,0);
SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES,0);
SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER,1);
SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE,0);
SDL_GL_SetSwapInterval(1);

Resize(ScreenWidth,ScreenHeight);

VideoFlags:=0;
if paramstr(1)='f' then begin
 VideoFlags:=VideoFlags or SDL_WINDOW_FULLSCREEN_DESKTOP;
 Fullscreen:=true;
 WrapCursor:=true;
 ScreenWidth:=1280;
 ScreenHeight:=720;
end;
for Index:=0 downto 0 do begin
 DepthBufferSizeCounter:=3;
 MultiSampleCounter:=0;
// writeln(DepthBufferSizeCounter shl 3,' ',1 shl MultiSampleCounter);
 SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE,DepthBufferSizeCounter shl 3);
 if MultiSampleCounter=0 then begin
  SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS,0);
  SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES,0);
 end else begin
  SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS,1);
  SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES,1 shl MultiSampleCounter);
 end;
 SurfaceWindow:=SDL_CreateWindow(pansichar(Title+' - Version '+Version+' - '+Copyright),(BestWidth-ScreenWidth) div 2,(BestHeight-ScreenHeight) div 2,ScreenWidth,ScreenHeight,SDL_WINDOW_OPENGL or SDL_WINDOW_SHOWN or SDL_WINDOW_RESIZABLE or VideoFlags);
 if assigned(SurfaceWindow) then begin
  SDL_EventState(SDL_DROPFILE,SDL_ENABLE);
  SurfaceContext:=SDL_GL_CreateContext(SurfaceWindow);
  if not assigned(SurfaceContext) then begin
   SDL_DestroyWindow(SurfaceWindow);
   SurfaceWindow:=nil;
   if Index=0 then begin
    exit;
   end else begin
    continue;
   end;
  end;
 end else begin
  exit;
 end;
 OK:=false;
 if InitOpenGL then begin
  ReadOpenGLCore;
  ReadImplementationProperties;
  ReadExtensions;
  OK:=true;
 end;
 if not (OK and assigned(glGenVertexArrays)) then begin
  if assigned(SurfaceContext) then begin
   SDL_GL_DeleteContext(SurfaceContext);
   SurfaceContext:=nil;
  end;
  SDL_DestroyWindow(SurfaceWindow);
  SurfaceWindow:=nil;
  if Index=0 then begin
   exit;
  end else begin
   continue;
  end;
 end;
 break;
end;

glGetIntegerv(GL_MAJOR_VERSION,@Major);
glGetIntegerv(GL_MINOR_VERSION,@Minor);

if ((Major>4) or ((Major=4) and (Minor>=5))) or
   (GL_ARB_clip_control and
    GL_ARB_shader_storage_buffer_object and
    ((Major>4) or ((Major=4) and (Minor>=1)))) then begin

 SDL_GL_SetSwapInterval(1);

 SDL_ShowCursor(ord(not FullScreen) and 1);

 SDL_SetRelativeMouseMode(ord(WrapCursor or FullScreen) and 1);

 StartPerformanceCounter:=SDL_GetPerformanceCounter;

 glEnable(GL_TEXTURE_CUBE_MAP_SEAMLESS);

 glGenVertexArrays(1,@EmptyVertexArrayObjectHandle);
 try

  BRDFLUTShader:=TBRDFLUTShader.Create;
  try

   FillChar(BRDFLUTFBO,SizeOf(TFBO),#0);
   BRDFLUTFBO.Width:=512;
   BRDFLUTFBO.Height:=512;
   BRDFLUTFBO.Depth:=0;
   BRDFLUTFBO.Textures:=1;
   BRDFLUTFBO.TextureFormats[0]:=GL_TEXTURE_RGBA16F;
   BRDFLUTFBO.Format:=GL_TEXTURE_RGBA16F;
   BRDFLUTFBO.SWrapMode:=wmGL_CLAMP_TO_EDGE;
   BRDFLUTFBO.TWrapMode:=wmGL_CLAMP_TO_EDGE;
   BRDFLUTFBO.RWrapMode:=wmGL_CLAMP_TO_EDGE;
   BRDFLUTFBO.MinFilterMode:=fmGL_LINEAR;
   BRDFLUTFBO.MagFilterMode:=fmGL_LINEAR;
   BRDFLUTFBO.Flags:=0;
   CreateFrameBuffer(BRDFLUTFBO);
   glBindFrameBuffer(GL_FRAMEBUFFER,BRDFLUTFBO.FBOs[0]);
   glDrawBuffer(GL_COLOR_ATTACHMENT0);
   glViewport(0,0,BRDFLUTFBO.Width,BRDFLUTFBO.Height);
   glClearColor(0.0,0.0,0.0,0.0);
   glClearDepth(1.0);
   glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);
   glDisable(GL_DEPTH_TEST);
   glDisable(GL_CULL_FACE);
   glCullFace(GL_BACK);
   glBindVertexArray(EmptyVertexArrayObjectHandle);
   BRDFLUTShader.Bind;
   glDrawArrays(GL_TRIANGLES,0,3);
   BRDFLUTShader.Unbind;
   glBindVertexArray(0);
   glBindFrameBuffer(GL_FRAMEBUFFER,0);

  finally
   FreeAndNil(BRDFLUTShader);
  end;

  try

   EnvMapGenShader:=TEnvMapGenShader.Create;
   try

    if true then begin
     ImageWidth:=1024;
     ImageHeight:=1024;
     EnvMapFBO.Width:=ImageWidth;
     EnvMapFBO.Height:=ImageHeight;
     EnvMapFBO.Depth:=0;
     EnvMapFBO.Textures:=1;
     EnvMapFBO.TextureFormats[0]:=GL_TEXTURE_RGBA16F;
     EnvMapFBO.Format:=GL_TEXTURE_RGBA16F;
     EnvMapFBO.SWrapMode:=wmGL_REPEAT;
     EnvMapFBO.TWrapMode:=wmGL_REPEAT;
     EnvMapFBO.RWrapMode:=wmGL_REPEAT;
     EnvMapFBO.MinFilterMode:=fmGL_LINEAR_MIPMAP_LINEAR;
     EnvMapFBO.MagFilterMode:=fmGL_LINEAR;
     EnvMapFBO.Flags:=FBOFlagMipMap or FBOFlagCubeMap;
     CreateFrameBuffer(EnvMapFBO);
     EnvMapGenShader.Bind;
     glActiveTexture(GL_TEXTURE0);
     glBindFrameBuffer(GL_FRAMEBUFFER,EnvMapFBO.FBOs[Index]);
     glDrawBuffer(GL_COLOR_ATTACHMENT0);
     glViewport(0,0,EnvMapFBO.Width shr Index,EnvMapFBO.Height shr Index);
     glClearColor(0.0,0.0,0.0,0.0);
     glClearDepth(1.0);
     glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);
     glDisable(GL_DEPTH_TEST);
     glDisable(GL_CULL_FACE);
     glCullFace(GL_BACK);
     glBindVertexArray(EmptyVertexArrayObjectHandle);
     glDrawArrays(GL_TRIANGLES,0,18);
     glBindVertexArray(0);
     glBindFrameBuffer(GL_FRAMEBUFFER,0);
     EnvMapTextureHandle:=EnvMapFBO.TextureHandles[0];
     EnvMapFBO.TextureHandles[0]:=0;
     DestroyFrameBuffer(EnvMapFBO);
     EnvMapGenShader.Unbind;
    end else begin
     EnvMapTextureHandle:=0;
     glGenTextures(1,@EnvMapTextureHandle);
     glBindTexture(GL_TEXTURE_CUBE_MAP,EnvMapTextureHandle);
     glTexParameteri(GL_TEXTURE_CUBE_MAP,GL_TEXTURE_WRAP_S,GL_REPEAT);
     glTexParameteri(GL_TEXTURE_CUBE_MAP,GL_TEXTURE_WRAP_T,GL_REPEAT);
     glTexParameteri(GL_TEXTURE_CUBE_MAP,GL_TEXTURE_WRAP_R,GL_REPEAT);
     glTexParameteri(GL_TEXTURE_CUBE_MAP,GL_TEXTURE_MIN_FILTER,GL_LINEAR_MIPMAP_LINEAR);
     glTexParameteri(GL_TEXTURE_CUBE_MAP,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
     RootPath:=IncludeTrailingPathDelimiter(IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)))+'envmap');
     for Index:=0 to 5 do begin
      MemoryStream:=TMemoryStream.Create;
      try
       TextureFileName:=RootPath+CubeMapFileNames[Index]+'.png';
       if not FileExists(TextureFileName) then begin
        TextureFileName:=RootPath+CubeMapFileNames[Index]+'.jpeg';
        if not FileExists(TextureFileName) then begin
         TextureFileName:=RootPath+CubeMapFileNames[Index]+'.jpg';
        end;
       end;
       MemoryStream.LoadFromFile(TextureFileName);
       ImageWidth:=2048;
       ImageHeight:=2048;
       if LoadImage(MemoryStream.Memory,MemoryStream.Size,ImageData,ImageWidth,ImageHeight) then begin
        try
         glTexImage2D(CubeMapTexs[Index],0,GL_SRGB8_ALPHA8,ImageWidth,ImageHeight,0,GL_RGBA,GL_UNSIGNED_BYTE,ImageData);
       finally
         FreeMem(ImageData);
        end;
       end;
      finally
       MemoryStream.Free;
      end;
     end;
    end;

    glBindTexture(GL_TEXTURE_CUBE_MAP,EnvMapTextureHandle);
    glTexParameteri(GL_TEXTURE_CUBE_MAP,GL_TEXTURE_BASE_LEVEL,0);
    glTexParameteri(GL_TEXTURE_CUBE_MAP,GL_TEXTURE_MAX_LEVEL,trunc(log2(Min(ImageWidth,ImageHeight))));
    glGenerateMipmap(GL_TEXTURE_CUBE_MAP);
    glBindTexture(GL_TEXTURE_CUBE_MAP,0);

    EnvMapFilterShader:=TEnvMapFilterShader.Create;
    try
     FillChar(EnvMapFBO,SizeOf(TFBO),#0);
     EnvMapFBO.Width:=ImageWidth;
     EnvMapFBO.Height:=ImageHeight;
     EnvMapFBO.Depth:=0;
     EnvMapFBO.Textures:=1;
     EnvMapFBO.TextureFormats[0]:=GL_TEXTURE_RGBA16F;
     EnvMapFBO.Format:=GL_TEXTURE_RGBA16F;
     EnvMapFBO.SWrapMode:=wmGL_REPEAT;
     EnvMapFBO.TWrapMode:=wmGL_REPEAT;
     EnvMapFBO.RWrapMode:=wmGL_REPEAT;
     EnvMapFBO.MinFilterMode:=fmGL_LINEAR_MIPMAP_LINEAR;
     EnvMapFBO.MagFilterMode:=fmGL_LINEAR;
     EnvMapFBO.Flags:=FBOFlagMipMap or FBOFlagMipMapLevelWiseFill or FBOFlagCubeMap;
     CreateFrameBuffer(EnvMapFBO);
     EnvMapFilterShader.Bind;
     for Index:=0 to EnvMapFBO.WorkMaxLevel do begin
      glActiveTexture(GL_TEXTURE0);
      if Index=0 then begin
       glBindTexture(GL_TEXTURE_CUBE_MAP,EnvMapTextureHandle);
      end else begin
       glBindTexture(GL_TEXTURE_CUBE_MAP,EnvMapFBO.TextureHandles[0]);
      end;
      glUniform1i(EnvMapFilterShader.uTexture,0);
      glUniform1i(EnvMapFilterShader.uMipMapLevel,Index);
      glUniform1i(EnvMapFilterShader.uMaxMipMapLevel,EnvMapFBO.WorkMaxLevel);
      glBindFrameBuffer(GL_FRAMEBUFFER,EnvMapFBO.FBOs[Index]);
      glDrawBuffer(GL_COLOR_ATTACHMENT0);
      glViewport(0,0,EnvMapFBO.Width shr Index,EnvMapFBO.Height shr Index);
      glClearColor(0.0,0.0,0.0,0.0);
      glClearDepth(1.0);
      glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);
      glDisable(GL_DEPTH_TEST);
      glDisable(GL_CULL_FACE);
      glCullFace(GL_BACK);
      glBindVertexArray(EmptyVertexArrayObjectHandle);
      glDrawArrays(GL_TRIANGLES,0,18);
      glBindVertexArray(0);
      glBindFrameBuffer(GL_FRAMEBUFFER,0);
     end;
     EnvMapFilterShader.Unbind;
    finally
     FreeAndNil(EnvMapFilterShader);
    end;

   finally
    FreeAndNil(EnvMapGenShader);
   end;

   try

    EnvMapDrawShader:=TEnvMapDrawShader.Create;
    try

     FillChar(HDRSceneFBO,SizeOf(TFBO),#0);
     HDRSceneFBO.Width:=ViewPortWidth;
     HDRSceneFBO.Height:=ViewPortHeight;
     HDRSceneFBO.Depth:=0;
     HDRSceneFBO.Textures:=1;
     HDRSceneFBO.TextureFormats[0]:=GL_TEXTURE_RGBA16F;
     HDRSceneFBO.Format:=GL_TEXTURE_RGBA16F;
     HDRSceneFBO.SWrapMode:=wmGL_CLAMP_TO_EDGE;
     HDRSceneFBO.TWrapMode:=wmGL_CLAMP_TO_EDGE;
     HDRSceneFBO.RWrapMode:=wmGL_CLAMP_TO_EDGE;
     HDRSceneFBO.MinFilterMode:=fmGL_LINEAR;
     HDRSceneFBO.MagFilterMode:=fmGL_LINEAR;
     HDRSceneFBO.Flags:=FBOFlagDepthBuffer;
     CreateFrameBuffer(HDRSceneFBO);
     try

      HDRToLDRShader:=THDRToLDRShader.Create;
      try

       FillChar(LDRSceneFBO,SizeOf(TFBO),#0);
       LDRSceneFBO.Width:=ViewPortWidth;
       LDRSceneFBO.Height:=ViewPortHeight;
       LDRSceneFBO.Depth:=0;
       LDRSceneFBO.Textures:=1;
       LDRSceneFBO.TextureFormats[0]:=GL_TEXTURE_RGBA8UB;
       LDRSceneFBO.Format:=GL_TEXTURE_RGBA8UB;
       LDRSceneFBO.SWrapMode:=wmGL_CLAMP_TO_EDGE;
       LDRSceneFBO.TWrapMode:=wmGL_CLAMP_TO_EDGE;
       LDRSceneFBO.RWrapMode:=wmGL_CLAMP_TO_EDGE;
       LDRSceneFBO.MinFilterMode:=fmGL_LINEAR;
       LDRSceneFBO.MagFilterMode:=fmGL_LINEAR;
       LDRSceneFBO.Flags:=FBOFlagDepthBuffer;
       CreateFrameBuffer(LDRSceneFBO);
       try

        AntialiasingShader:=TAntialiasingShader.Create;
        try

         if assigned(GLTFOpenGL) then begin
          GLTFOpenGL.Upload;
         end;
         try

          ShadingShaders[false,false]:=TShadingShader.Create(false,false);
          try

           ShadingShaders[false,true]:=TShadingShader.Create(false,true);
           try

            ShadingShaders[true,false]:=TShadingShader.Create(true,false);
            try

             ShadingShaders[true,true]:=TShadingShader.Create(true,true);
             try

              ExtendedBlitRectShader:=TExtendedBlitRectShader.Create;
              try

               ConsoleInstance:=TConsole.Create;
               try

                ConsoleInstance.Upload;

                MainLoop;

               finally
                FreeAndNil(ConsoleInstance);
               end;

              finally
               FreeAndNil(ExtendedBlitRectShader);
              end;

             finally
              FreeAndNil(ShadingShaders[true,true]);
             end;

            finally
             FreeAndNil(ShadingShaders[true,false]);
            end;

           finally
            FreeAndNil(ShadingShaders[false,true]);
           end;

          finally
           FreeAndNil(ShadingShaders[false,false]);
          end;

         finally
          if assigned(GLTFOpenGL) then begin
           try
            GLTFOpenGL.Unload;
           finally
            FreeAndNil(GLTFOpenGL);
           end;
          end;
         end;

        finally
         FreeAndNil(AntialiasingShader);
        end;

       finally
        DestroyFrameBuffer(LDRSceneFBO);
       end;

      finally
       FreeAndNil(HDRToLDRShader);
      end;

     finally
      DestroyFrameBuffer(HDRSceneFBO);
     end;

    finally
     EnvMapDrawShader.Free;
    end;

   finally
    DestroyFrameBuffer(EnvMapFBO);
   end;

  finally
   DestroyFrameBuffer(BRDFLUTFBO);
  end;

  if EnvMapTextureHandle>0 then begin
   glDeleteTextures(1,@EnvMapTextureHandle);
  end;

 finally
  glDeleteVertexArrays(1,@EmptyVertexArrayObjectHandle);
 end;

end else begin

 SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR or
                          SDL_MESSAGEBOX_BUTTON_RETURNKEY_DEFAULT,
                          PAnsiChar('Fatal error'),
                          PAnsiChar('Too old OpenGL version! You do need at least OpenGL version 4.5 or alternatively at least OpenGL 4.1 with the GL_ARB_clip_control and GL_ARB_shader_storage_buffer_object extensions'),
                          SurfaceWindow);

end;

if assigned(SurfaceContext) then begin
 SDL_GL_DeleteContext(SurfaceContext);
 SurfaceContext:=nil;
end;
if assigned(SurfaceWindow) then begin
 SDL_DestroyWindow(SurfaceWindow);
 SurfaceWindow:=nil;
end;

SDL_Quit;

end.
