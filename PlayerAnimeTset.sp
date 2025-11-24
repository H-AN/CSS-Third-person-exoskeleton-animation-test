#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>

/******
 * 制作额外动画 需要骨骼动画支持
 * 需要第一人称动画配合(如果需要)
 * 实现原理
 * 1.创建玩家克隆实体,此实体拥有玩家模型骨骼信息
 * 2.创建骨骼动画实体,此实体拥有骨骼动画信息
 * 3.将克隆实体绑定骨骼动画实体,驱动骨骼动画即可驱动玩家克隆实体
 * 4.将动画实体绑定至玩家实体跟随,角度移动等实现动画附加
 * 5.(可选)隐藏第一人称能看到自己的第三人称动画实体,以免视线受阻,即每个人只能看见别人的动画实体
 * 6.(可选/必选?)勾住实体动画是否结束,若动画结束直接删除两个实体
 * 7.(未来)制作滑铲,踢腿等外部动画,需要绑定按键逻辑与动画交互逻辑 即
 * 使用 SetVariantString("动画名称(滑铲)"); AcceptEntityInput(PlayerAnim[client], "SetAnimation");
 * 来设置外部动画, 使用外部动画的时候 设置玩家模型为不可见,并设置动画实体为可见
 * 当动画结束时 直接删除动画实体与克隆实体/或隐藏等待下次使用(节省资源)
******/

public Plugin myinfo =
{
    name = "外部附加动画", 
    author = "H-AN", 
    description = "外部附加动画,骨骼动画", 
    version = "1.0", 
    url = "github https://github.com/H-AN"
};

#define EF_BONEMERGE                (1 << 0)
#define EF_NOSHADOW                 (1 << 4)
#define EF_BONEMERGE_FASTCULL       (1 << 7)
#define EF_NORECEIVESHADOW          (1 << 6)
#define EF_PARENT_ANIMATES          (1 << 9)
#define HIDEHUD_ALL                 (1 << 2)
#define HIDEHUD_CROSSHAIR           (1 << 8)


int PlayerAnim[MAXPLAYERS+1];
int PlayerClone[MAXPLAYERS+1];

enum struct Config
{
    ConVar OwnerCanSee;
    ConVar EntDuration;
}
Config g_AnimeConfig;

public void OnPluginStart()
{
    /*****
     * 提供两个测试用cvar 
     * 1 开启隐藏自己的实体(自己是否能看见自己)
     * 2 实体持续时间
    *****/
    g_AnimeConfig.OwnerCanSee = CreateConVar("anime_owner", "1", "自己是否可以看见自己的动画实体? 1 能看见 0 看不见");
    g_AnimeConfig.EntDuration = CreateConVar("anime_duration", "10.0", "动画实体与克隆实体存在的寿命时长");

    HookEvent("player_death", OnPlayerDeath, EventHookMode_Pre);
    RegConsoleCmd("sm_anime", command_anime);
    RegConsoleCmd("sm_setanime", command_setanime);
}

public void OnMapStart()
{
    PrecacheModel("models/player/custom_player/kodua_foxhound/css_emotes_beta.mdl", true); //预缓存
    
}

public Action command_anime(client ,args )
{
    /*****
     * 创建实体 
     * 可用于runcmd 等按键使用的时候(注意好CD/频率/限制等 以免重复创建)
     * 创建后可以立即播放一次动画无需外部设置 生成时直接使用动画即可
    *****/
    CreatePlayerCloneWithAnimation(client);

    return Plugin_Handled;
}

public Action command_setanime(client , args)
{
    /*****
     * 直接设置动画
     * 以实体索引 PlayerAnim[client] 来找到实体 
     * 直接设置qc动画名称即可 
    *****/
    if(PlayerAnim[client] <= 0)
    {
        PrintToChat(client, "动画实体不存在");
        return Plugin_Handled;
    }

    if (args < 1)
    {
        return Plugin_Handled;
    }

    /*****
     * 提供一个测试命令
     * 输入 !setanime Emote_Bendy
     * 实体存在期间 将播放这个骨骼动画(qc名称)
    *****/

    char arg1[32];
    GetCmdArg(1, arg1, sizeof(arg1));

    SetVariantString(arg1); 
    AcceptEntityInput(PlayerAnim[client], "SetAnimation");

    return Plugin_Handled;
}


public Action OnPlayerDeath(Handle event, const char[] name, bool dontBroadcast)  //玩家死亡删除两个实体
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if (IsValidClient(client))
	{
		KillAnime(client); 
        KillClone(client);
	}

    return Plugin_Continue;
}


public void CreatePlayerCloneWithAnimation(int client)
{
    if (!IsValidClient(client) || IsFakeClient(client) || !IsPlayerAlive(client))
        return;

    if(PlayerAnim[client])
    {
        KillAnime(client);
    }

    if(PlayerClone[client])
    {
        KillClone(client);
    }
        
    float vec[3], ang[3];
    GetClientAbsOrigin(client, vec);
    GetClientAbsAngles(client, ang);

    int animEnt = CreateEntityByName("prop_dynamic");
    if (animEnt == -1) return;

    char EntName[16];
    FormatEx(EntName, sizeof(EntName), "AnimeEnt%i", GetRandomInt(1000000, 9999999)); //动画名称 根据名称绑定实体

    DispatchKeyValue(animEnt, "targetname", EntName);
    DispatchKeyValue(animEnt, "model", "models/player/custom_player/kodua_foxhound/css_emotes_beta.mdl"); //骨骼动画模型

    DispatchKeyValue(animEnt, "solid", "0");
	DispatchKeyValue(animEnt, "rendermode", "10");

    ActivateEntity(animEnt);
	DispatchSpawn(animEnt);

    SetEntPropEnt(animEnt, Prop_Send, "m_hOwnerEntity", client); //设置实体归属者

    TeleportEntity(animEnt, vec, ang, NULL_VECTOR);

    SetEntPropFloat(animEnt, Prop_Send, "m_flModelScale", 1.0); //尺寸
    SetEntityRenderColor(animEnt, 255, 255, 255, 255); //颜色 阿尔法值

    int clone = CreateEntityByName("prop_dynamic");
    if (clone == -1) return;

    char PlayerModel[64];
    GetEntPropString(client, Prop_Data, "m_ModelName", PlayerModel, sizeof(PlayerModel));
    
    PrecacheModel(PlayerModel, true);

    DispatchKeyValue(clone, "model", PlayerModel);
    DispatchSpawn(clone);

    SetEntPropEnt(clone, Prop_Send, "m_hOwnerEntity", client);

    SetEntityMoveType(clone, MOVETYPE_NONE);

    TeleportEntity(clone, vec, ang, NULL_VECTOR);

    SetEntPropFloat(clone, Prop_Send, "m_flModelScale", 1.0); //尺寸
    SetEntityRenderColor(clone, 255, 255, 255, 255); //颜色 阿尔法值

    SetVariantString(EntName);
	AcceptEntityInput(clone, "SetParent", clone, clone, 0);

    SetEntProp(clone, Prop_Send, "m_fEffects", EF_BONEMERGE | EF_NOSHADOW | EF_NORECEIVESHADOW | EF_BONEMERGE_FASTCULL| EF_PARENT_ANIMATES); //骨骼绑定

    SetVariantString("Emote_Bendy"); //骨骼动画 qc 名字
    AcceptEntityInput(animEnt, "SetDefaultAnimation", -1, -1, 0);

    SetEntPropFloat(animEnt, Prop_Send, "m_flPlaybackRate", 1.0); //动画速率 

    PlayerAnim[client] = EntIndexToEntRef(animEnt); //保存动画实体索引
    PlayerClone[client] = EntIndexToEntRef(clone); //玩家克隆实体索引

    SetVariantString("!activator");
    AcceptEntityInput(PlayerAnim[client], "SetParent", client); //绑定动画实体与玩家

    SDKHook(PlayerClone[client], SDKHook_SetTransmit, SetTransmit_CallBack); //第一人称自己看不到自己的动画实体 (可选,注释掉即可自己看到自己的第三人称动画)

    float duration = GetConVarFloat(g_AnimeConfig.EntDuration);
    
    char Clone[64], Anim[64];
    Format(Clone, sizeof(Clone), "!self,Kill,,%0.1f,-1", duration); //持续时间 到了自己删除(可选/删除或者隐藏)
    DispatchKeyValue(PlayerClone[client], "OnUser1", Clone);
    AcceptEntityInput(PlayerClone[client], "FireUser1");

    Format(Anim, sizeof(Anim), "!self,Kill,,%0.1f,-1", duration); //持续时间 到了自己删除(可选/删除或者隐藏)
    DispatchKeyValue(PlayerAnim[client], "OnUser1", Anim);
    AcceptEntityInput(PlayerAnim[client], "FireUser1");
}

public Action SetTransmit_CallBack(entity, viewer)
{
    new owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
    if(viewer > 0 && viewer <= MaxClients)
    {
        if(owner == viewer && !GetConVarBool(g_AnimeConfig.OwnerCanSee))
        {
            return Plugin_Handled;
        }     
    }
    return Plugin_Continue;
} 


void KillAnime(int client)
{
	if (!PlayerAnim[client])
		return;

	int Ent = EntRefToEntIndex(PlayerAnim[client]);
	if (Ent && Ent != INVALID_ENT_REFERENCE && IsValidEntity(Ent))
	{
		char EntName[50];
		GetEntPropString(Ent, Prop_Data, "m_iName", EntName, sizeof(EntName));
		SetVariantString(EntName);
		AcceptEntityInput(client, "ClearParent", Ent, Ent, 0);
		DispatchKeyValue(Ent, "OnUser1", "!self,Kill,,1.0,-1");
		AcceptEntityInput(Ent, "FireUser1");

		PlayerAnim[client] = 0;
	} else
	{
		PlayerAnim[client] = 0;
	}
}

void KillClone(int client)
{
	if (!PlayerClone[client])
		return;

	int Ent = EntRefToEntIndex(PlayerClone[client]);
	if (Ent && Ent != INVALID_ENT_REFERENCE && IsValidEntity(Ent))
	{
		DispatchKeyValue(Ent, "OnUser1", "!self,Kill,,1.0,-1");
		AcceptEntityInput(Ent, "FireUser1");
		PlayerClone[client] = 0;
	} else
	{
		PlayerClone[client] = 0;
	}
}

stock bool IsValidClient(client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client));
}




