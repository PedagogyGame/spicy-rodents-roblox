#include "AerHockey.h"
#include "Modules/ModuleManager.h"
#include "ProceduralMeshComponent.h"
#include "Camera/CameraComponent.h"
#include "Components/InputComponent.h"
#include "Components/PointLightComponent.h"
#include "Components/RectLightComponent.h"
#include "Engine/PointLight.h"
#include "Engine/RectLight.h"
#include "Engine/Canvas.h"
#include "Engine/Engine.h"
#include "Engine/TextureCube.h"
#include "UObject/ConstructorHelpers.h"
#include "Engine/World.h"
#include "Materials/Material.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Kismet/GameplayStatics.h"
#include "GameFramework/PlayerController.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Dom/JsonObject.h"
#include "Sound/SoundWaveProcedural.h"

IMPLEMENT_PRIMARY_GAME_MODULE(FDefaultGameModuleImpl,AerHockey,"AerHockey");

AAerArena::AAerArena(){
    PrimaryActorTick.bCanEverTick=true;
    SceneRoot=CreateDefaultSubobject<USceneComponent>(TEXT("ArenaRoot"));SetRootComponent(SceneRoot);
}

UProceduralMeshComponent* AAerArena::BuildPart(const FString& Name,const TArray<TSharedPtr<FJsonValue>>& Sections){
    auto* Mesh=NewObject<UProceduralMeshComponent>(this,*Name);
    Mesh->SetupAttachment(RootComponent);Mesh->RegisterComponent();
    Mesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);
    // Gameplay collisions are continuous 2-D sweeps, independent of triangle tessellation.
    int32 SectionIndex=0;
    for(const auto& Value:Sections){
        auto O=Value->AsObject();TArray<FVector> Vertices,Normals;TArray<int32> Indices;
        auto& P=O->GetArrayField(TEXT("positions"));auto& N=O->GetArrayField(TEXT("normals"));
        for(int32 i=0;i<P.Num();i+=3){
            Vertices.Emplace(-P[i]->AsNumber()*100,P[i+1]->AsNumber()*100,P[i+2]->AsNumber()*100);
            Normals.Emplace(-N[i]->AsNumber(),N[i+1]->AsNumber(),N[i+2]->AsNumber());
        }
        auto& I=O->GetArrayField(TEXT("indices"));
        for(int32 i=0;i<I.Num();i+=3){Indices.Add(I[i]->AsNumber());Indices.Add(I[i+1]->AsNumber());Indices.Add(I[i+2]->AsNumber());}
        TArray<FVector2D> UV;TArray<FLinearColor> Colors;TArray<FProcMeshTangent> Tangents;
        Mesh->CreateMeshSection_LinearColor(SectionIndex,Vertices,Indices,Normals,UV,Colors,Tangents,false);
        Mesh->SetMaterial(SectionIndex,SurfaceMaterials[O->GetIntegerField(TEXT("material"))]);SectionIndex++;
    }
    return Mesh;
}

void AAerArena::BeginPlay(){
    Super::BeginPlay();
    FString Text;
    if(!FFileHelper::LoadFileToString(Text,*(FPaths::ProjectContentDir()/TEXT("Data/Arena.json")))){
        LoadError=TEXT("Missing Content/Data/Arena.json");UE_LOG(LogTemp,Error,TEXT("%s"),*LoadError);return;
    }
    TSharedPtr<FJsonObject> Data;
    if(!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text),Data)||!Data.IsValid()){
        LoadError=TEXT("Arena geometry JSON could not be read");return;
    }
    UMaterialInterface* Base=LoadObject<UMaterialInterface>(nullptr,TEXT("/Game/AirHockey/Materials/M_Surface.M_Surface"));
    if(!Base){LoadError=TEXT("Run Tools/setup_arena.py in Unreal first to create the arena material and map.");return;}
    for(auto& Value:Data->GetArrayField(TEXT("materials"))){
        auto O=Value->AsObject();auto& C=O->GetArrayField(TEXT("color"));
        auto* M=UMaterialInstanceDynamic::Create(Base,this);
        M->SetVectorParameterValue(TEXT("Tint"),FLinearColor(C[0]->AsNumber(),C[1]->AsNumber(),C[2]->AsNumber()));
        M->SetScalarParameterValue(TEXT("Metal"),O->GetNumberField(TEXT("metal")));
        M->SetScalarParameterValue(TEXT("Rough"),O->GetNumberField(TEXT("rough")));
        M->SetScalarParameterValue(TEXT("Glow"),O->GetNumberField(TEXT("glow")));
        SurfaceMaterials.Add(M);
    }
    auto Parts=Data->GetObjectField(TEXT("parts"));
    Table=BuildPart(TEXT("SculptedTable"),Parts->GetArrayField(TEXT("table")));
    MalletA=BuildPart(TEXT("GlacierMallet"),Parts->GetArrayField(TEXT("malletA")));
    MalletB=BuildPart(TEXT("EmberMallet"),Parts->GetArrayField(TEXT("malletB")));
    Puck=BuildPart(TEXT("CarbonPuck"),Parts->GetArrayField(TEXT("puck")));
    BuildLighting();bReady=true;
    UE_LOG(LogTemp,Display,TEXT("AER_ARENA_READY: 4 Blender parts, %d materials, 240Hz continuous physics"),SurfaceMaterials.Num());
}

void AAerArena::BuildLighting(){
    // A closed studio rather than a template sky keeps the ceramic and LEDs readable.
    auto* Floor=NewObject<UProceduralMeshComponent>(this,TEXT("StudioFloor"));
    Floor->SetupAttachment(RootComponent);Floor->RegisterComponent();
    TArray<FVector> V{{-2000,-2000,-1},{2000,-2000,-1},{2000,2000,-1},{-2000,2000,-1}};
    TArray<int32> I{0,2,1,0,3,2};TArray<FVector> N;N.Init(FVector::UpVector,4);
    Floor->CreateMeshSection_LinearColor(0,V,I,N,TArray<FVector2D>(),TArray<FLinearColor>(),TArray<FProcMeshTangent>(),false);
    auto* M=UMaterialInstanceDynamic::Create(SurfaceMaterials[0]->GetMaterial(),this);
    M->SetVectorParameterValue(TEXT("Tint"),FLinearColor(.018,.026,.039));M->SetScalarParameterValue(TEXT("Rough"),.55);M->SetScalarParameterValue(TEXT("Metal"),.25);
    Floor->SetMaterial(0,M);
    auto* Key=GetWorld()->SpawnActor<ARectLight>(FVector(0,-40,380),FRotator(-90,0,0));
    auto* Rect=Cast<URectLightComponent>(Key->GetLightComponent());
    Rect->SetIntensity(12000);Rect->SetSourceWidth(260);Rect->SetSourceHeight(260);
    Rect->SetLightColor(FLinearColor(.75,.87,1));Rect->SetAttenuationRadius(1200);
    auto AddPoint=[&](FVector P,FLinearColor C,float Intensity){
        auto* L=GetWorld()->SpawnActor<APointLight>(P,FRotator::ZeroRotator);
        auto* LC=Cast<UPointLightComponent>(L->GetLightComponent());LC->SetIntensity(Intensity);LC->SetLightColor(C);LC->SetAttenuationRadius(700);LC->SetSourceRadius(65);
    };
    AddPoint(FVector(-160,-40,150),FLinearColor(.02,.65,1),1500);
    AddPoint(FVector(160,160,220),FLinearColor(1,.22,.10),2300);
    AddPoint(FVector(0,-210,170),FLinearColor(.55,.75,1),900);
}

void AAerArena::PlayTone(float Hz,float Seconds,float Volume){
    auto* Wave=NewObject<USoundWaveProcedural>(this);
    Wave->SetSampleRate(22050);Wave->NumChannels=1;Wave->Duration=Seconds;Wave->SoundGroup=SOUNDGROUP_Effects;
    TArray<int16> Samples;int32 Count=Seconds*22050;Samples.SetNum(Count);
    for(int32 i=0;i<Count;i++){
        float T=float(i)/22050;float E=FMath::Exp(-T*38)*(1-float(i)/Count);
        Samples[i]=FMath::Sin(2*PI*Hz*T)*E*Volume*18000;
    }
    Wave->QueueAudio(reinterpret_cast<uint8*>(Samples.GetData()),Samples.Num()*sizeof(int16));
    UGameplayStatics::PlaySound2D(this,Wave);
}

void AAerArena::SwapEnds(){HumanSide=1-HumanSide;}
void AAerArena::Tick(float Delta){
    Super::Tick(Delta);if(!bReady)return;
    if(!bWaitingForPlayer)Accumulator+=FMath::Min(Delta,.10f);
    while(Accumulator>=Aer::Game::Step){Game.Tick(Aer::Game::Step,HumanSide,true);Accumulator-=Aer::Game::Step;}
    if(Game.hitSerial!=LastHit){PlayTone(340+Aer::Length(Game.velocity)*70,.06,.32);LastHit=Game.hitSerial;}
    if(Game.goalSerial!=LastGoal){PlayTone(740,.45,.65);LastGoal=Game.goalSerial;}
    MalletA->SetRelativeLocation(FVector(-Game.paddles[0].p.x*100,Game.paddles[0].p.y*100,90));
    MalletB->SetRelativeLocation(FVector(-Game.paddles[1].p.x*100,Game.paddles[1].p.y*100,90));
    Puck->SetRelativeLocation(FVector(-Game.puck.x*100,Game.puck.y*100,90));
}

AAerPawn::AAerPawn(){
    PrimaryActorTick.bCanEverTick=true;
    RootComponent=CreateDefaultSubobject<USceneComponent>(TEXT("PlayerPosition"));
    Camera=CreateDefaultSubobject<UCameraComponent>(TEXT("Eyes"));Camera->SetupAttachment(RootComponent);Camera->SetFieldOfView(64);
    Camera->PostProcessSettings.bOverride_AutoExposureMethod=true;
    Camera->PostProcessSettings.AutoExposureMethod=EAutoExposureMethod::AEM_Manual;
    Camera->PostProcessSettings.bOverride_AutoExposureBias=true;Camera->PostProcessSettings.AutoExposureBias=9.0;
    static ConstructorHelpers::FObjectFinder<UTextureCube> Ambient(TEXT("/Engine/MapTemplates/Sky/DaylightAmbientCubemap.DaylightAmbientCubemap"));
    if(Ambient.Succeeded()){
        Camera->PostProcessSettings.AmbientCubemap=Ambient.Object;
        Camera->PostProcessSettings.bOverride_AmbientCubemapIntensity=true;
        Camera->PostProcessSettings.AmbientCubemapIntensity=.5;
    }
    Camera->PostProcessSettings.bOverride_BloomIntensity=true;Camera->PostProcessSettings.BloomIntensity=.55;
}
void AAerPawn::SetupPlayerInputComponent(UInputComponent* IC){
    Super::SetupPlayerInputComponent(IC);
    IC->BindKey(EKeys::R,IE_Pressed,this,&AAerPawn::ResetMatch);
    IC->BindKey(EKeys::P,IE_Pressed,this,&AAerPawn::PauseMatch);
    IC->BindKey(EKeys::Escape,IE_Pressed,this,&AAerPawn::PauseMatch);
    IC->BindKey(EKeys::Tab,IE_Pressed,this,&AAerPawn::SwapEnds);
    IC->BindKey(EKeys::SpaceBar,IE_Pressed,this,&AAerPawn::Serve);
    IC->BindKey(EKeys::LeftMouseButton,IE_Pressed,this,&AAerPawn::Serve);
    IC->BindKey(EKeys::V,IE_Pressed,this,&AAerPawn::ToggleView);
}
void AAerPawn::Tick(float Delta){
    Super::Tick(Delta);
    if(!Arena)Arena=Cast<AAerArena>(UGameplayStatics::GetActorOfClass(this,AAerArena::StaticClass()));
    if(!Arena)return;
    const double S=Arena->HumanSide?1:-1;
    if(Arena->bOverview){Camera->SetFieldOfView(72);SetActorLocation(FVector(0,0,600));SetActorRotation(FRotator(-90,-90,0));}
    else {Camera->SetFieldOfView(64);FVector P(0,S*182,170);SetActorLocation(P);SetActorRotation((FVector(0,-S*18,90)-P).Rotation());}
    auto* PC=Cast<APlayerController>(Controller);if(!PC)return;
    PC->bShowMouseCursor=true;
    FVector O,D;
    if(PC->DeprojectMousePositionToWorld(O,D)&&D.Z<-.001){
        FVector P=O+D*((90-O.Z)/D.Z);
        Arena->Game.SetTarget(Arena->HumanSide,{-P.X/100,P.Y/100});
    }
}
void AAerPawn::ResetMatch(){if(Arena){Arena->Game.Reset();Arena->bWaitingForPlayer=true;}}
void AAerPawn::PauseMatch(){if(Arena)Arena->Game.paused=!Arena->Game.paused;}
void AAerPawn::SwapEnds(){if(Arena)Arena->SwapEnds();}
void AAerPawn::Serve(){if(Arena&&Arena->Game.countdown>0){Arena->bWaitingForPlayer=false;Arena->Game.Serve();}}
void AAerPawn::ToggleView(){if(Arena)Arena->bOverview=!Arena->bOverview;}

void AAerHUD::DrawHUD(){
    Super::DrawHUD();if(!Canvas)return;
    auto* A=Cast<AAerArena>(UGameplayStatics::GetActorOfClass(this,AAerArena::StaticClass()));if(!A)return;
    float W=Canvas->SizeX,H=Canvas->SizeY;UFont* Font=GEngine->GetLargeFont();
    auto Center=[&](const FString& S,float Y,float Scale,FLinearColor Color){float TW,TH;GetTextSize(S,TW,TH,Font,Scale);DrawText(S,Color,(W-TW)*.5,Y,Font,Scale);};
    DrawRect(FLinearColor(.008,.015,.025,.88),0,0,W,108);
    DrawText(TEXT("A E R  /  0 1"),FLinearColor(.8,.9,.95),28,25,Font,.75);
    DrawText(TEXT("PRECISION AIR HOCKEY"),FLinearColor(.4,.56,.64),28,64,GEngine->GetSmallFont(),1);
    Center(FString::Printf(TEXT("%02d     :     %02d"),A->Game.score[0],A->Game.score[1]),22,1.7,FLinearColor(.9,.98,1));
    DrawText(TEXT("GLACIER"),FLinearColor(.04,.85,1),W*.5-165,77,GEngine->GetSmallFont(),1);
    DrawText(TEXT("EMBER"),FLinearColor(1,.3,.18),W*.5+103,77,GEngine->GetSmallFont(),1);
    DrawText(A->HumanSide?TEXT("YOU / EMBER"):TEXT("YOU / GLACIER"),FLinearColor(.7,.83,.9),W-180,37,Font,.65);
    DrawRect(FLinearColor(.008,.015,.025,.82),0,H-48,W,48);
    Center(TEXT("MOUSE  move mallet     SPACE  serve     TAB  switch end     V  camera     P  pause     R  new match"),H-33,.50,FLinearColor(.6,.73,.8));
    if(!A->LoadError.IsEmpty())Center(A->LoadError,H*.45,.65,FLinearColor(1,.3,.2));
    else if(A->Game.winner>=0){Center(A->Game.winner==A->HumanSide?TEXT("MATCH WON"):TEXT("MATCH COMPLETE"),H*.31,1.7,FLinearColor(.8,.95,1));Center(TEXT("FIRST TO 7  /  PRESS R TO PLAY AGAIN"),H*.31+65,.65,FLinearColor::White);}
    else if(A->Game.paused)Center(TEXT("PAUSED  /  P TO RESUME"),H*.31,1.1,FLinearColor::White);
    else if(A->bWaitingForPlayer)Center(TEXT("PRESS SPACE TO PLAY"),H*.25,.9,FLinearColor(.8,.95,1));
    else if(A->Game.countdown>0)Center(TEXT("READY  /  SPACE TO SERVE"),H*.25,.9,FLinearColor(.8,.95,1));
}

AAerGameMode::AAerGameMode(){DefaultPawnClass=AAerPawn::StaticClass();HUDClass=AAerHUD::StaticClass();}
void AAerGameMode::BeginPlay(){
    Super::BeginPlay();GetWorld()->SpawnActor<AAerArena>();
    if(auto* PC=UGameplayStatics::GetPlayerController(this,0)){
        PC->bShowMouseCursor=true;FInputModeGameAndUI Mode;Mode.SetHideCursorDuringCapture(false);Mode.SetLockMouseToViewportBehavior(EMouseLockMode::DoNotLock);PC->SetInputMode(Mode);
    }
}
