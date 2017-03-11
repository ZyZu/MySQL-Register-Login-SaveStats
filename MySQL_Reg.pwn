// MySQL Regisztráció rendszer by kurta999
// Verzió: 3.0
// Last Update: 2017.03.11

#include <a_samp>
#include <a_mysql> // http://forum.sa-mp.com/showthread.php?t=56564
#include <a_zcmd> // http://forum.sa-mp.com/showthread.php?t=91354

// Ha öreg verziójú az a_mysql.inc-je, akkor kiírjuk neki hogy frissítsen
#if !defined cache_get_query_exec_time
	#error "Frissítsd a MySQL (a_mysql.inc) függvénykönyvtárad az R41-2 re, vagy újabbra!"
#endif


#define             NINCS_REG_CSILLAG // Rakd a kommenttárba, ha a jelszót a játékosnak a regisztráció dialógusban csillagozni akarod.

#define ChangeNameDialog(%1) \
    ShowPlayerDialog(%1, DIALOG_CHANGENAME, DIALOG_STYLE_INPUT, !"{" #XCOLOR_RED "}Névváltás", !"{" #XCOLOR_GREEN "}Lentre írd be az új neved! \nHa régóta játszol már, akkor a névváltás több másodpercig is eltarthat!\n\n{" #XCOLOR_RED "}Ahogy megváltoztattad, rögtön változtasd meg a neved a SAMP-ba!", !"Változtatás", !"Mégse")

// SendClientMessagef beágyazása
new g_szFormatString[144];
#define SendClientMessagef(%1,%2,%3) \
    SendClientMessage(%1, %2, (format(g_szFormatString, sizeof(g_szFormatString), %3), g_szFormatString))

// gpci beágyazása
#if !defined gpci
native gpci(playerid, const serial[], maxlen);
#endif

new
	year,
	month,
	day,
	hour,
	minute,
	second;

new // Direkt adok hozzá + 1 karaktert, mivel valahol a \0 karaktert is tárolni kell. (Ez 4 karakter, de kell az 5. is, mivel ott tárolja a \0-t! ['a', 'n', 'y', 'á', 'd', '\0'])
	g_szQuery[512 +1],
	g_szDialogFormat[4096],
 	g_szIP[16 +1],
    MySQL:g_MySQL;

// Bit flagok
enum e_PLAYER_FLAGS (<<= 1)
{
	e_LOGGED_IN = 1,
	e_FIRST_SPAWN
}
new
	e_PLAYER_FLAGS:g_PlayerFlags[MAX_PLAYERS char];

new
	g_pQueryQueue[MAX_PLAYERS];

// MySQL beállítások, alapból ezek azok a wamp-nál, csak a tábla nevét módosítsd arra, amilyen néven létrehoztad, nekem itt a 'samp'
#define MYSQL_HOST 				"host"
#define MYSQL_USER 				"user"
#define MYSQL_PASS 				"pass"
#define MYSQL_DB   				"data"

// Üzenet, amit akkor ír ki, ha a lekérdezés befejezése elott lelép a játékos
#define QUERY_COLLISION(%0) \
	printf("Query collision \" #%0 \"! PlayerID: %d, queue: %d, g_pQueryQueue: %d", playerid, queue, g_pQueryQueue[playerid])

// RRGGBBAA
#define COLOR_GREEN 			0x33FF33AA
#define COLOR_RED				0xFF0000AA
#define COLOR_YELLOW			0xFF9900AA
#define COLOR_PINK 				0xFF66FFAA

// RRGGBB
#define XCOLOR_GREEN 			33FF33
#define XCOLOR_RED 				FF0000
#define XCOLOR_BLUE				33CCFF
#define XCOLOR_YELLOW			FF9900
#define XCOLOR_WHITE			FFFFFF

// Dialóg ID
enum
{
	DIALOG_LOGIN = 20000,
	DIALOG_REGISTER,
	DIALOG_CHANGENAME,
	DIALOG_CHANGEPASS,
	DIALOG_FINDPLAYER
}

// isnull by Y_Less
#define isnull(%1) \
	((!(%1[0])) || (((%1[0]) == '\1') && (!(%1[1]))))

public OnFilterScriptInit()
{
	// MySQL
	print("<< MySQL >> Kapcsolódás a(z) " MYSQL_HOST ", " MYSQL_USER " adatbázis " MYSQL_DB "!");
	mysql_log(ALL);
	g_MySQL = mysql_connect(MYSQL_HOST, MYSQL_USER, MYSQL_PASS, MYSQL_DB);

	if(mysql_errno())
	{
		print("<< MySQL >> Kapcsolódás sikertelen! A mód bezárul..");
		SendRconCommand(!"exit");
		return 1;
	}

	print("<< MySQL >> Kapcsolódás a(z) " MYSQL_HOST " sikeres!");
	print("<< MySQL >> Adatbázis " MYSQL_DB " kiválasztva.\n");
  	return 1;
}

public OnFilterScriptExit()
{
	mysql_close(g_MySQL); // Kapcsolat bontása
	return 1;
}

public OnPlayerConnect(playerid)
{
	SetPlayerColor(playerid, (random(0xFFFFFF) << 8) | 0xFF); // GetPlayerColor() javítása
	g_pQueryQueue[playerid]++;

	mysql_format(g_MySQL, g_szQuery, sizeof(g_szQuery), "SELECT `reg_id` FROM `players` WHERE `name` = '%s'", pName(playerid));
	mysql_tquery(g_MySQL, g_szQuery, "THREAD_OnPlayerConnect", "dd", playerid, g_pQueryQueue[playerid]);
	return 1;
}

public OnPlayerDisconnect(playerid, reason)
{
	g_pQueryQueue[playerid]++;
	return SavePlayer(playerid, GetPVarInt(playerid, "RegID"));
}

forward THREAD_OnPlayerConnect(playerid, queue);
public THREAD_OnPlayerConnect(playerid, queue)
{
	// Ha a játékos csatlakozik vagy lelép, akkor a "g_pQueryQueue[playerid]" értéke mindig növekedik.
	// Lekérdezésnél átvisszük ennek az értékét a "queue" nevu paraméterben, amit majd a lekérdezés lefutásánál ellenorzünk.
	// Ha a játékos lelépett, akkor "g_pQueryQueue[playerid]" egyel több lett, tehát nem egyenlo a "queue" paraméter értékével.
	// Ez esetben a lekérdezés nem fog lefutni, hanem egy figyelmezeto üzenetet fog kiírni a konzolva, hogy "query collision".
	// Nagyon fontos ez, mivel ha van egy lekérdezés, ami lekérdez valami "titkos" adatot az adatbázisból,
	// közben belaggol a a mysql szerver, a lekérdezés eltart 5 másodpercig, feljön egy másik játékos és annak fogja kiírni az adatokat,
	// mivel a lekérdezés lefutása közben lelépett a játékos és egy másik jött a helyére. Erre van ez a védelem, így ettol egyáltalán nem kell tartani.
	// Sima lekérdezéseknél (ház betöltés, egyéb betöltés, frissítés, stb.. szarságok) ilyen helyen nem szükséges ez a védelem.
	if(g_pQueryQueue[playerid] != queue) return QUERY_COLLISION(THREAD_OnPlayerConnect);

	new
		szFetch[12],
		serial[64];
	cache_get_value_index(0, 0, szFetch);
	SetPVarInt(playerid, "LineID", strval(szFetch));
	// Ez itt egy "átmeneti változó", ami tárolja, hogy mi a reg id-je a játékosnak.
	// Ha nulla, akkor nincs regisztrálva (mivel az SQL 0-t ad vissza, ha nemlétezo a sor), ellentétben pedig igen.

	g_PlayerFlags{playerid} = e_PLAYER_FLAGS:0; // Nullázuk az értékét, nem elég a nulla, kell elé a változó tagja is, különben figyelmeztet a fordító.
    if(!IsPlayerNPC(playerid)) // Csak játékosokra vonatkozik
	{
		SetPVarInt(playerid, "RegID", -1);

		GetPlayerIp(playerid, g_szIP, sizeof(g_szIP));
		gpci(playerid, serial, sizeof(serial));

		getdate(year, month, day);
		gettime(hour, minute, second);

		mysql_format(g_MySQL, g_szQuery, sizeof(g_szQuery), "INSERT INTO `connections`(id, name, ip, serial, time) VALUES(0, '%s', '%s', '%s', '%02d.%02d.%02d/%02d.%02d.%02d')", pName(playerid), g_szIP, serial, year, month, day, hour, minute, second);
		mysql_tquery(g_MySQL, g_szQuery);

		// Autologin

		// Leftuttatunk egy lekérdezést, ami ha befejezodött, akkor meghívódik a "THREAD_Autologin" callback.
		// A régebbi pluginnal ez egy funkcióban ment, szóval ha a mysql szerver belaggolt és a lekérdezés eltartott 5 másodpercig,
		// akkor 5 másodpercig megfagyott a szerver.
		// Itt nem fog megfagyni semeddig a szerver, mivel létrehoz neki egy új szálat, és az a szál fagy meg míg nem fut le a lekérdezés.
		// Lefutás után pedig meghívja a "THREAD_Autologin" callbackot. Ez már logikus, hogy az alap szálon (main thread)-on fut.
		//
		// Fenti lekérdezéssel is szintén ez a helyzet, viszont ott nem vagyunk kiváncsi a kapott értékekre.
		// Az a lefutása során az "OnQueryFinish" callbackot hívja meg, viszont itt nem történik semmi.
		// Ugyanaz a helyzet az összes lekérdezéssel, ha kiváncsi lennék az értékére, akkor ugyanúgy a callback alá raknám a dolgokat, mint itt.
		mysql_format(g_MySQL, g_szQuery, sizeof(g_szQuery), "SELECT * FROM `players` WHERE `name` = '%s' AND `ip` = '%s'", pName(playerid), g_szIP);
		mysql_tquery(g_MySQL, g_szQuery, "THREAD_Autologin", "dd", playerid, g_pQueryQueue[playerid]);
	}
  	return 1;
}

forward THREAD_Autologin(playerid, queue);
public THREAD_Autologin(playerid, queue)
{
	if(g_pQueryQueue[playerid] != queue) return QUERY_COLLISION(THREAD_Autologin);

	new
	    rows,
	    fields;
	
	cache_get_row_count(rows);
    cache_get_field_count(fields);
    
	if(rows) // Ha a sor nem üres
	{
		LoginPlayer(playerid);
		SendClientMessage(playerid, COLOR_GREEN, "Automatikusan bejelentkeztél!");
	}
	return 1;
}

public OnPlayerRequestClass(playerid, classid)
{
	if(IsPlayerNPC(playerid)) return 1;

    //printf("%d", g_PlayerFlags{playerid} & e_LOGGED_IN);
	if(!(g_PlayerFlags{playerid} & e_LOGGED_IN)) // Felmutatjuk neki a megfelelo dialógot
	{
		if(GetPVarInt(playerid, "LineID"))
		{
			LoginDialog(playerid);
		}
		else
		{
			RegisterDialog(playerid);
		}
	}
	return 1;
}

public OnPlayerRequestSpawn(playerid)
{
	if(IsPlayerNPC(playerid)) return 1;

	if(!(g_PlayerFlags{playerid} & e_LOGGED_IN)) // Felmutatjuk neki a megfelelo dialógot
	{
		if(GetPVarInt(playerid, "LineID"))
		{
			LoginDialog(playerid);
		}
		else
		{
			RegisterDialog(playerid);
		}
	}
	return 1;
}

public OnPlayerSpawn(playerid)
{
	// Ha eloször spawnol, akkor odaadjuk neki a pénzt. Mivel skinválasztásnál nem lehet pénzt adni a játékosnak!
	if(!(g_PlayerFlags{playerid} & e_FIRST_SPAWN))
	{
		ResetPlayerMoney(playerid);
		GivePlayerMoney(playerid, GetPVarInt(playerid, "Cash"));
		DeletePVar(playerid, "Cash");

		g_PlayerFlags{playerid} |= e_FIRST_SPAWN;
	}

	// Ütésstílus beállítása
	SetPlayerFightingStyle(playerid, GetPVarInt(playerid, "Style"));
	return 1;
}


// Y_Less
NameCheck(const aname[])
{
    new
        i,
        ch;
    while ((ch = aname[i++]) && ((ch == ']') || (ch == '[') || (ch == '(') || (ch == ')') || (ch == '_') || (ch == '$') || (ch == '@') || (ch == '.') || (ch == '=') || ('0' <= ch <= '9') || ((ch |= 0x20) && ('a' <= ch <= 'z')))) {}
    return !ch;
}

public OnDialogResponse(playerid, dialogid, response, listitem, inputtext[])
{
	switch(dialogid)
	{
		case DIALOG_LOGIN:
		{
			if(!response)
			    return LoginDialog(playerid);

			if(g_PlayerFlags{playerid} & e_LOGGED_IN)
			{
				SendClientMessage(playerid, COLOR_RED, "Már be vagy jelentkezve.");
				return 1;
			}

			if(isnull(inputtext))
			{
				SendClientMessage(playerid, COLOR_RED, "Nem írtál be semilyen jelszót!");
				LoginDialog(playerid);
				return 1;
			}

			if(!(3 <= strlen(inputtext) <= 20))
			{
				SendClientMessage(playerid, COLOR_RED, "Rossz jelszó hosszúság! 3 - 20");
				LoginDialog(playerid);
				return 1;
			}

			// %e -  Kiszuri az adatot, SQL injection elkerülése végett. Bovebben itt olvashatsz róla: http://sampforum.hu/index.php?topic=9285.0
			mysql_format(g_MySQL, g_szQuery, sizeof(g_szQuery), "SELECT * FROM `players` WHERE `name` = '%s' AND `pass` COLLATE `utf8_bin` LIKE '%e'", pName(playerid), inputtext);
			mysql_tquery(g_MySQL, g_szQuery, "THREAD_DialogLogin", "dd", playerid, g_pQueryQueue[playerid]);
		}
		case DIALOG_REGISTER:
		{
			if(!response)
				return RegisterDialog(playerid);

			if(isnull(inputtext))
			{
				SendClientMessage(playerid, COLOR_RED, "Nem írtál be semilyen jelszót!");
				RegisterDialog(playerid);
				return 1;
			}

			if(!(3 <= strlen(inputtext) <= 20))
			{
				SendClientMessage(playerid, COLOR_RED, "Rossz jelszó hosszúság! 3 - 20");
				RegisterDialog(playerid);
				return 1;
			}

			mysql_format(g_MySQL, g_szQuery, sizeof(g_szQuery), "SELECT `reg_id` FROM `players` WHERE `name` = '%s'", pName(playerid));
			mysql_tquery(g_MySQL, g_szQuery, "THREAD_Register_1", "dsd", playerid, inputtext, g_pQueryQueue[playerid]);
		}
		case DIALOG_CHANGENAME:
		{
			if(!response)
				return 0;

			if(!(3 <= strlen(inputtext) <= 20))
			{
				SendClientMessage(playerid, COLOR_RED, "Nem megfelelo hosszú a neved! 3 és 20 karakter között legyen!");

				ChangeNameDialog(playerid);
				return 1;
			}

			if(!NameCheck(inputtext))
			{
				SendClientMessage(playerid, COLOR_RED, "Nem megfelelo név! Csak ezek a karakterek lehetnek benne: {" #XCOLOR_GREEN "}A-Z, 0-9, [], (), $, @. {" #XCOLOR_RED "}Ezenkívül helyet nem tartamlazhat!");

				ChangeNameDialog(playerid);
				return 1;
			}

			if(!strcmp(inputtext, pName(playerid), true))
			{
				SendClientMessage(playerid, COLOR_RED, "Jelenleg is ez a neved! Írj be egy másikat!");

				ChangeNameDialog(playerid);
				return 1;
			}

			mysql_format(g_MySQL, g_szQuery, sizeof(g_szQuery), "SELECT `reg_id` FROM `players` WHERE `name` = '%e'", inputtext);
			mysql_tquery(g_MySQL, g_szQuery, "THREAD_Changename", "dsd", playerid, inputtext, g_pQueryQueue[playerid]);
		}
		case DIALOG_CHANGEPASS:
		{
			if(!response)
				return 0;

			if(!(3 <= strlen(inputtext) <= 20))
			{
				SendClientMessage(playerid, COLOR_RED, "Nem megfelelo hosszú a jelszavad! 3 és 20 karakter között legyen!");

				ShowPlayerDialog(playerid, DIALOG_CHANGEPASS, DIALOG_STYLE_INPUT, "Jelszóváltás", "Lentre írd be az új jelszavad! \n\n", "Változtatás", "Mégse");
				return 1;
			}

			mysql_format(g_MySQL, g_szQuery, sizeof(g_szQuery), "SELECT `pass` FROM `players` WHERE `reg_id` = %d", GetPVarInt(playerid, "RegID"));
			mysql_tquery(g_MySQL, g_szQuery, "THREAD_Changepass", "dsd", playerid, inputtext, g_pQueryQueue[playerid]);
		}
		case DIALOG_FINDPLAYER:
		{
			if(!response)
				return 0;

			mysql_format(g_MySQL, g_szQuery, sizeof(g_szQuery), "SELECT * FROM `players` WHERE `name` = '%s'", inputtext);
			mysql_tquery(g_MySQL, g_szQuery, "THREAD_Findplayer", "dsd", playerid, inputtext, g_pQueryQueue[playerid]);
		}
	}
	return 1;
}

forward THREAD_DialogLogin(playerid, queue);
public THREAD_DialogLogin(playerid, queue)
{
	if(g_pQueryQueue[playerid] != queue) return QUERY_COLLISION(THREAD_DialogLogin);

	new
	    rows,
	    fields;
	    
    cache_get_row_count(rows);
    cache_get_field_count(fields);
	
	if(rows != 1)
	{
		SendClientMessage(playerid, COLOR_RED, "HIBA: Rossz jelszó.");
		LoginDialog(playerid);
		return 1;
	}

	LoginPlayer(playerid);
	GetPlayerIp(playerid, g_szIP, sizeof(g_szIP));

	mysql_format(g_MySQL, g_szQuery, sizeof(g_szQuery), "UPDATE `players` SET `ip` = '%s' WHERE `reg_id` = %d", g_szIP, GetPVarInt(playerid, "RegID"));
	mysql_tquery(g_MySQL, g_szQuery);

	SendClientMessage(playerid, COLOR_GREEN, !"Sikersen bejelentkeztél!");
	return 1;
}

forward THREAD_Register_1(playerid, password[], queue);
public THREAD_Register_1(playerid, password[], queue)
{
	if(g_pQueryQueue[playerid] != queue) return QUERY_COLLISION(THREAD_Register_1);

	new
	    rows,
	    fields;

    cache_get_row_count(rows);
    cache_get_field_count(fields);

	if(rows)
	{
		SendClientMessage(playerid, COLOR_RED, "MySQL sorok száma nem 0, valami hiba történt a kiválasztás közben!");
		SendClientMessage(playerid, COLOR_RED, "Ezt a hibát jelezd a tulajdonosnak! Kickelve lettél, mert ebbol hiba keletkezhet!");

		printf("MySQL rosw > 1 (%d, %s)", playerid, password);
		Kick(playerid);
		return 1;
	}

	getdate(year, month, day);
	gettime(hour, minute, second);

	GetPlayerIp(playerid, g_szIP, sizeof(g_szIP));

	mysql_format(g_MySQL, g_szQuery, sizeof(g_szQuery), "INSERT INTO `players`(reg_id, name, ip, pass, reg_date, laston) VALUES(0, '%s', '%s', '%e', '%02d.%02d.%02d/%02d.%02d.%02d', '%02d.%02d.%02d/%02d.%02d.%02d')", pName(playerid), g_szIP, password, year, month, day, hour, minute, second, year, month, day, hour, minute, second);
	mysql_tquery(g_MySQL, g_szQuery, "THREAD_Register_2", "dsd", playerid, password, g_pQueryQueue[playerid]);
	return 1;
}

forward THREAD_Register_2(playerid, password[], queue);
public THREAD_Register_2(playerid, password[], queue)
{
	if(g_pQueryQueue[playerid] != queue) return QUERY_COLLISION(THREAD_Register_2);

	new
		iRegID = cache_insert_id();
	SetPVarInt(playerid, "RegID", iRegID); // Játékos Regisztrációs ID-jét beállítuk arra, amelyik sorba írtunk elobb ( INSERT INTO )
	SetPVarInt(playerid, "Style", 4);
	g_PlayerFlags{playerid} |= e_LOGGED_IN;

	SendClientMessagef(playerid, COLOR_GREEN, "Sikeresen regisztráltál! A jelszavad: {" #XCOLOR_RED "}%s. {" #XCOLOR_GREEN "}Felhasználó ID: {" #XCOLOR_BLUE "}%d", password, iRegID);
	SendClientMessage(playerid, COLOR_PINK, "Ennyi lenne a MySQL regisztáció {" #XCOLOR_BLUE "}:)");
	return 1;
}

forward THREAD_Changename(playerid, inputtext[], queue);
public THREAD_Changename(playerid, inputtext[], queue)
{
	if(g_pQueryQueue[playerid] != queue) return QUERY_COLLISION(THREAD_Changename);

	new
	    rows,
	    fields;

    cache_get_row_count(rows);
    cache_get_field_count(fields);

	if(rows)
	{
		SendClientMessage(playerid, COLOR_RED, "HIBA: Ez a név már használatban van!");
		SendClientMessage(playerid, COLOR_GREEN, "Írj be egy más nevet, vagy menj a 'Mégse' gombra!");

		ChangeNameDialog(playerid);
		return 1;
	}

	new
		szOldName[MAX_PLAYER_NAME + 1],
		pRegID = GetPVarInt(playerid, "RegID");
	GetPlayerName(playerid, szOldName, sizeof(szOldName));

	if(SetPlayerName(playerid, inputtext) != 1)
	{
		SendClientMessage(playerid, COLOR_RED, "Nem megfelelo név! Írj be egy másikat!");

		ChangeNameDialog(playerid);
		return 1;
	}

	getdate(year, month, day);
	gettime(hour, minute, second);

	mysql_format(g_MySQL, g_szQuery, sizeof(g_szQuery), "INSERT INTO `namechanges`(id, reg_id, oldname, newname, time) VALUES(0, %d, '%s', '%s', '%02d.%02d.%02d/%02d.%02d.%02d')", pRegID, szOldName, inputtext, year, month, day, hour, minute, second);
	mysql_tquery(g_MySQL, g_szQuery);

	mysql_format(g_MySQL, g_szQuery, sizeof(g_szQuery), "UPDATE `players` SET `name` = '%s' WHERE `reg_id` = %d", inputtext, pRegID);
	mysql_tquery(g_MySQL, g_szQuery);

	SendClientMessagef(playerid, COLOR_YELLOW, "Sikeresen átváltottad a neved! Új neved: {" #XCOLOR_WHITE "}%s.", inputtext);
	return 1;
}

forward THREAD_Changepass(playerid, password[], queue);
public THREAD_Changepass(playerid, password[], queue)
{
	if(g_pQueryQueue[playerid] != queue) return QUERY_COLLISION(THREAD_Changepass);

	new
	    szOldPass[21],
	    szEscaped[21],
	    pRegID = GetPVarInt(playerid, "RegID");
	cache_get_value_index(0, 0, szOldPass);

	mysql_format(g_MySQL, g_szQuery, sizeof(g_szQuery), "UPDATE `players` SET `pass` = '%e' WHERE `reg_id` = %d", password, pRegID);
	mysql_tquery(g_MySQL, g_szQuery);

	getdate(year, month, day);
	gettime(hour, minute, second);

	mysql_format(g_MySQL, g_szQuery, sizeof(g_szQuery), "INSERT INTO `namechanges_p`(id, reg_id, name, oldpass, newpass, time) VALUES(0, %d, '%s', '%s', '%s', '%02d.%02d.%02d/%02d.%02d.%02d')", pRegID, pName(playerid), szOldPass, szEscaped, year, month, day, hour, minute, second);
	mysql_tquery(g_MySQL, g_szQuery);

	SendClientMessagef(playerid, COLOR_YELLOW, "Sikeresen átállítotad a jelszavad! Új jelszavad: {" #XCOLOR_GREEN "}%s", password);
	return 1;
}

forward THREAD_Findplayer(playerid, inputtext[], queue);
public THREAD_Findplayer(playerid, inputtext[], queue)
{
	if(g_pQueryQueue[playerid] != queue) return QUERY_COLLISION(THREAD_Findplayer);

	new
		szFetch[12],
		szRegDate[24],
		szLaston[24],
		iData[6];
		
	cache_get_value_index_int(0, 0, iData[0]); // regid
	cache_get_value_index(0, 4, szRegDate);
	cache_get_value_index(0, 5, szLaston);
	cache_get_value_index_int(0, 6, iData[1]);// money
	cache_get_value_index_int(0, 7, iData[2]); // score
	cache_get_value_index_int(0, 8, iData[3]); // kills
	cache_get_value_index_int(0, 9, iData[4]); // deaths
	cache_get_value_index_int(0, 10, iData[5]); // style

	switch(iData[5])
	{
		case FIGHT_STYLE_NORMAL: szFetch = "Normál";
	   	case FIGHT_STYLE_BOXING: szFetch = "Boxoló";
	   	case FIGHT_STYLE_KUNGFU: szFetch = "Kungfu";
		case FIGHT_STYLE_KNEEHEAD: szFetch = "Kneehead";
		case FIGHT_STYLE_GRABKICK: szFetch = "Grabkick";
		case FIGHT_STYLE_ELBOW: szFetch = "Elbow";
	}

	// Üzenet elküldése
	SendClientMessagef(playerid, COLOR_RED, "Név: %s, ID: %d, RegID: %d, Pénz: %d, Pont: %d", inputtext, playerid, iData[0], iData[1], iData[2]);
	SendClientMessagef(playerid, COLOR_YELLOW, "Ölések: %d, Halálok: %d, Arány: %.2f, Ütés Stílus: %s", iData[3], iData[4], (iData[3] && iData[4]) ? (floatdiv(iData[3], iData[4])) : (0.0), szFetch);
	SendClientMessagef(playerid, COLOR_GREEN, "Regisztáció ideje: {" #XCOLOR_BLUE "}%s{" #XCOLOR_GREEN "}, Utuljára a szerveren: {" #XCOLOR_BLUE "}%s", szRegDate, szLaston);
	return 1;
}

public OnPlayerDeath(playerid, killerid, reason)
{
	if(IsPlayerConnected(killerid) && killerid != INVALID_PLAYER_ID)
	{
		SetPVarInt(killerid, "Kills", GetPVarInt(killerid, "Kills") + 1);
	}

	SetPVarInt(playerid, "Deaths", GetPVarInt(playerid, "Deaths") + 1);
	return 1;
}

// Statisztika felmutató
CMD:stats(playerid, params[])
{
	mysql_format(g_MySQL, g_szQuery, sizeof(g_szQuery), "SELECT `reg_date`, `laston` FROM `players` WHERE `reg_id` = %d", GetPVarInt(playerid, "RegID")); // Kiválasztjuk a reg_date és a laston mezot
	mysql_tquery(g_MySQL, g_szQuery, "THREAD_Stats", "dd", playerid, g_pQueryQueue[playerid]);
	return 1;
}

forward THREAD_Stats(playerid, queue);
public THREAD_Stats(playerid, queue)
{
	if(g_pQueryQueue[playerid] != queue) return QUERY_COLLISION(THREAD_Stats);

	new
		RegDate[24],
		Laston[24],
		szStyle[24],
		Kills = GetPVarInt(playerid, "Kills"),
		Deaths = GetPVarInt(playerid, "Deaths");
	cache_get_value_index(0, 0, RegDate);
	cache_get_value_index(0, 1, Laston);

	switch(GetPlayerFightingStyle(playerid))
	{
		case FIGHT_STYLE_NORMAL: szStyle = "Normál";
	   	case FIGHT_STYLE_BOXING: szStyle = "Boxoló";
	   	case FIGHT_STYLE_KUNGFU: szStyle = "Kungfu";
		case FIGHT_STYLE_KNEEHEAD: szStyle = "Kneehead";
		case FIGHT_STYLE_GRABKICK: szStyle = "Grabkick";
		case FIGHT_STYLE_ELBOW: szStyle = "Elbow";
	}

	// Üzenet elküldése
	SendClientMessagef(playerid, COLOR_RED, "Név: %s, ID: %d, RegID: %d, Pénz: %d, Pont: %d", pName(playerid), playerid, GetPVarInt(playerid, "RegID"), GetPlayerMoney(playerid), GetPlayerScore(playerid));
	SendClientMessagef(playerid, COLOR_YELLOW, "Ölések: %d, Halálok: %d, Arány: %.2f, Ütés Stílus: %s", Kills, Deaths, (Kills && Deaths) ? (floatdiv(Kills, Deaths)) : (0.0), szStyle);
	SendClientMessagef(playerid, COLOR_GREEN, "Regisztáció ideje: {" #XCOLOR_BLUE "}%s{" #XCOLOR_GREEN "}, Utuljára a szerveren: {" #XCOLOR_BLUE "}%s", RegDate, Laston);
	return 1;
}
/*
CMD:kill(playerid, params[])
{
	SetPlayerHealth(playerid, 0.0);
	return 1;
}

CMD:flag(playerid, params[])
{
	SendClientMessagef(playerid, -1, "Logged: %d, FirstSpawn: %d", g_PlayerFlags{playerid} & e_LOGGED_IN, g_PlayerFlags{playerid} & e_FIRST_SPAWN);
	return 1;
}
*/
CMD:changename(playerid, params[])
{
	ChangeNameDialog(playerid);
	return 1;
}

CMD:changepass(playerid, params[])
{
	ShowPlayerDialog(playerid, DIALOG_CHANGEPASS, DIALOG_STYLE_PASSWORD, "Jelszóváltás", "Lentre írd be az új jelszavad! \n\n", "Változtatás", "Mégse");
	return 1;
}

CMD:findplayer(playerid, params[])
{
	if(isnull(params)) return SendClientMessage(playerid, COLOR_RED, "HASZNÁLAT: /findplayer <Játékos Névrészlet>");
	if(strlen(params) > MAX_PLAYER_NAME) return SendClientMessage(playerid, COLOR_RED, "HIBA: Túl hosszú a részlet, maximum 24 karakter lehet!");

	mysql_format(g_MySQL, g_szQuery, sizeof(g_szQuery), "SELECT `name` FROM `players` WHERE `name` LIKE '%s%s%s'", "%%", params, "%%");
	mysql_tquery(g_MySQL, g_szQuery, "THREAD_FindplayerDialog", "dsd", playerid, params, g_pQueryQueue[playerid]);
	return 1;
}

forward THREAD_FindplayerDialog(playerid, reszlet[], queue);
public THREAD_FindplayerDialog(playerid, reszlet[], queue)
{
	if(g_pQueryQueue[playerid] != queue) return QUERY_COLLISION(THREAD_FindplayerDialog);

	new
	    rows,
	    fields;

    cache_get_row_count(rows);
    cache_get_field_count(fields);

	if(!rows)
	{
		SendClientMessagef(playerid, COLOR_RED, "Nincs találat a(z) '%s' részletre!", reszlet);
		return 1;
	}
	else if(rows > 180)
	{
		SendClientMessagef(playerid, COLOR_RED, "A(z) '%s' részletre több, mint 180 találad van! < %d >!", reszlet, rows);
		return 1;
	}

	new
	    x,
	    szName[MAX_PLAYER_NAME],
	    str[64];
	g_szDialogFormat[0] = EOS;
	for( ; x != rows; x++)
	{
		cache_get_value_index(x, 0, szName);
		strcat(g_szDialogFormat, szName);
		strcat(g_szDialogFormat, "\n");
	}

	format(str, sizeof(str), "Találatok a(z) '%s' részletre.. (%d)", reszlet, x);
	ShowPlayerDialog(playerid, DIALOG_FINDPLAYER, DIALOG_STYLE_LIST, str, g_szDialogFormat, "Megtekint", "Mégse");
	return 1;
}

/////////////////////////////////////////
stock LoginDialog(playerid)
{
	new
	    str[64];
	format(str, sizeof(str), "{" #XCOLOR_WHITE "}Bejelentkezés: {%06x}%s(%d)", GetPlayerColor(playerid) >>> 8, pName(playerid), playerid);
	ShowPlayerDialog(playerid, DIALOG_LOGIN, DIALOG_STYLE_PASSWORD, str, !"{" #XCOLOR_GREEN "}Üdvözöllek a \n\n{" #XCOLOR_BLUE "}My{" #XCOLOR_YELLOW "}SQL {" #XCOLOR_GREEN "}teszt szerveren! \n\nTe már regisztálva vagy. Lentre írd be a jelszavad", !"Bejelentkezés", !"Mégse");
	return 1;
}

stock RegisterDialog(playerid)
{
	new
	    str[64];
	format(str, sizeof(str), "{" #XCOLOR_WHITE "}Regisztráció: {%06x}%s(%d)", GetPlayerColor(playerid) >>> 8, pName(playerid), playerid);

	#if defined NINCS_REG_CSILLAG
		ShowPlayerDialog(playerid, DIALOG_REGISTER, DIALOG_STYLE_INPUT, str, !"{" #XCOLOR_GREEN "}Üdvözöllek a \n\n{" #XCOLOR_BLUE "}My{" #XCOLOR_YELLOW "}SQL {" #XCOLOR_GREEN "}teszt szerveren! \n\nItt még nem regisztráltál. Lentre írd be a jelszavad", !"Regisztáció", !"Mégse");
	#else
		ShowPlayerDialog(playerid, DIALOG_REGISTER, DIALOG_STYLE_PASSWORD, str, !"{" #XCOLOR_GREEN "}Üdvözöllek a \n\n{" #XCOLOR_BLUE "}My{" #XCOLOR_YELLOW "}SQL {" #XCOLOR_GREEN "}teszt szerveren! \n\nItt még nem regisztráltál. Lentre írd be a jelszavad", !"Regisztáció", !"Mégse");
	#endif
	return 1;
}

/* Bejelentkezés */
stock LoginPlayer(playerid)
{
	new
		iPVarSet[6],
		iRegID = GetPVarInt(playerid, "LineID");
	// Ha a line ID 0, tehát a MySQL nem adott vissza sorokat, akkor semmiképp sem jelentkezhez be!
	// Ennek nem szabadna elofordulnia, de biztonság kedvéért teszek rá védelmet.
	if(!iRegID) return printf("HIBA: Rossz reg ID! Játékos: %s(%d) (regid: %d)", pName(playerid), playerid, iRegID);

	SetPVarInt(playerid, "RegID", iRegID); // RegID-t beállítjuk
	cache_get_value_index_int(0, 0, iPVarSet[0]);  // RegID
	cache_get_value_index_int(0, 6, iPVarSet[1]); // Money
	cache_get_value_index_int(0, 7, iPVarSet[2]); // Score
	cache_get_value_index_int(0, 8, iPVarSet[3]); // Kills
	cache_get_value_index_int(0, 9, iPVarSet[4]); // Deaths
    cache_get_value_index_int(0, 10, iPVarSet[5]); // Fightingstyle

	SetPVarInt(playerid, "Cash", iPVarSet[1]); // A pénzét egy PVar-ban tároljuk, mert a skinválasztásnál nemlehet a játékos pénzét állítani.
	SetPlayerScore(playerid, iPVarSet[2]);

	SetPVarInt(playerid, "Kills", iPVarSet[3]);
	SetPVarInt(playerid, "Deaths", iPVarSet[4]);
	SetPVarInt(playerid, "Style", iPVarSet[5]);

	g_PlayerFlags{playerid} |= e_LOGGED_IN;
	return 1;
}

stock SavePlayer(playerid, regid)
{
	if(IsPlayerNPC(playerid)) return 1;

	// Ha nincs bejelentkezve és még nem spawnolt le, akkor nem mentjük. Ezt ajánlatos itthagyni, mivel ezmiatt nekem sok bug keletkezett!
	if(g_PlayerFlags{playerid} & (e_LOGGED_IN | e_FIRST_SPAWN) == (e_LOGGED_IN | e_FIRST_SPAWN))
	{
		getdate(year, month, day);
		gettime(hour, minute, second);

		mysql_format(g_MySQL, g_szQuery, sizeof(g_szQuery), "UPDATE `players` SET `laston` = '%02d.%02d.%02d/%02d.%02d.%02d', `money` = %d, `score` = %d, `kills` = %d, `deaths` = %d, `fightingstyle` = '%d' WHERE `reg_id` = %d",
		year, month, day, hour, minute, second, GetPlayerMoney(playerid), GetPlayerScore(playerid), GetPVarInt(playerid, "Kills"), GetPVarInt(playerid, "Deaths"), GetPlayerFightingStyle(playerid),
		regid);

		mysql_tquery(g_MySQL, g_szQuery);
		// %02d azt jelenti, hogyha a szám egyjegyu (1, 5, 7, stb... ), akkor tegyen elé egy 0-t. Pl: 05, 07.
		// Ezt általában idore használják, mivel így 'érthetobb'.
		// Ez ugyanúgy muködik %03d-vel %04d-vel, és így továb... ^
	}
	return 1;
}

stock pName(playerid)
{
	static // "Helyi" globális változó
		s_szName[MAX_PLAYER_NAME];
	GetPlayerName(playerid, s_szName, sizeof(s_szName));
	return s_szName;
}

/* SQL Tábla */
/*
CREATE TABLE IF NOT EXISTS `connections` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(21) NOT NULL,
  `ip` varchar(16) NOT NULL,
  `serial` varchar(128) NOT NULL,
  `time` varchar(24) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM  DEFAULT CHARSET=latin1;

CREATE TABLE IF NOT EXISTS `namechanges` (
  `id` smallint(5) NOT NULL AUTO_INCREMENT,
  `reg_id` mediumint(8) NOT NULL,
  `oldname` varchar(21) NOT NULL,
  `newname` varchar(21) NOT NULL,
  `time` varchar(24) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `reg_id` (`reg_id`)
) ENGINE=MyISAM  DEFAULT CHARSET=latin1;

CREATE TABLE IF NOT EXISTS `namechanges_p` (
  `id` smallint(5) NOT NULL AUTO_INCREMENT,
  `reg_id` mediumint(8) NOT NULL,
  `name` varchar(24) NOT NULL,
  `oldpass` varchar(21) NOT NULL,
  `newpass` varchar(21) NOT NULL,
  `time` varchar(24) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `reg_id` (`reg_id`)
) ENGINE=MyISAM  DEFAULT CHARSET=latin1;

CREATE TABLE IF NOT EXISTS `players` (
  `reg_id` mediumint(8) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(24) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL,
  `ip` varchar(20) NOT NULL,
  `pass` varchar(20) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL,
  `reg_date` varchar(24) NOT NULL,
  `laston` varchar(24) NOT NULL,
  `money` int(11) NOT NULL DEFAULT '0',
  `score` int(11) NOT NULL DEFAULT '0',
  `kills` mediumint(11) unsigned NOT NULL DEFAULT '0',
  `deaths` mediumint(11) unsigned NOT NULL DEFAULT '0',
  `fightingstyle` enum('4','5','6','7','15','16') NOT NULL DEFAULT '4',
  PRIMARY KEY (`reg_id`),
  KEY `name` (`name`)
) ENGINE=MyISAM  DEFAULT CHARSET=latin1 ROW_FORMAT=DYNAMIC;
*/

