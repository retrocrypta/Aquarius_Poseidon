/*
-- Menu handling
-- Copyright (c) 2021 by Alastair M. Robinson

-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.

-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty
-- of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.

-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/

#include <stdio.h>

#include "font.h"
#include "user_io.h"
#include "osd.h"
#include "menu.h"
#include "keyboard.h"
#include "spi.h"
#include "timer.h"

#include "config.h"

#include "gamepadkeys.h"

/* Not currently using hotkeys */
#undef MENU_HOTKEYS

#define OSD_ROWS OSDNLINE
#define OSD_COLS (OSDLINELEN/8)

#define menurows OSD_ROWS

static struct menu_entry *menu;
static int menu_visible=0;
static int menu_autohide=0;
char menu_longpress;

static int currentrow;

#ifdef MENU_HOTKEYS
static struct hotkey *hotkeys;
#endif

#ifdef CONFIG_JOYKEYS_TOGGLE
int joykeys_active=0;
#else
#define joykeys_active 1
#endif

void Menu_Draw(int currentrow)
{
	int i;
	struct menu_entry *m=menu;
	for(i=0;i<OSD_ROWS;++i)
	{
		OsdWriteStart(i,i==currentrow,0);
		OsdPutChar(' ');
		OsdPuts(m->label);
		OsdWriteEnd();
		m++;
	}
}


void Menu_Set(struct menu_entry *head)
{
	menu=head;
	currentrow=menurows-1;
	Menu_Draw(currentrow);
}


#ifdef MENU_HOTKEYS
void Menu_SetHotKeys(struct hotkey *head)
{
	hotkeys=head;
}
#endif


void Menu_ShowHide(int visible)
{
	if(visible<0)
		menu_visible=!menu_visible;
	else
		menu_visible=visible;
	OsdShowHide(menu_visible);
#ifdef CONFIG_JOYKEYS_TOGGLE
	HW_INTERCEPT(0)=menu_visible|joykeys_active;
#else
	HW_INTERCEPT(0)=menu_visible;
#endif
}

int Menu_Visible()
{
	return(menu_visible);
}

/* Analogue joystick support - left with weak linkage so it can be overriden */

__weak void Menu_JoystickToAnalogue(int *ana,int joy, int sensitivity)
{
	int a=*ana;
	int min=-0x7f00,max=0x7f00;
	if(joy&2)
	{
		max=-sensitivity<<8;
		a-=sensitivity;
	}
	else if(joy&1)
	{
		min=sensitivity<<8;
		a+=sensitivity;
	}
	else
		a=(a*15)>>4;
	if(a<min)
		a=min;
	if(a>max)
		a=max;
	*ana=a;
}


__weak void Menu_Joystick(int port,int joymap)
{
	#ifdef CONFIG_EXTJOYSTICK
	user_io_digital_joystick_ext(port, joymap);
	#else
	user_io_digital_joystick(port, joymap);
	#endif
}


/* Key -> gamepad mapping.  Weak linkage to allow overrides.
   FIXME - needs to be wider to allow for extra buttons. */
#ifdef CONFIG_JOYKEYS
__weak unsigned char joy_keymap[]=
{
	KEY_CAPSLOCK,
	KEY_LSHIFT,
	KEY_ALT,
	KEY_LCTRL,
	KEY_W,
	KEY_S,
	KEY_A,
	KEY_D,
	KEY_ENTER,
	KEY_RSHIFT,
	KEY_ALTGR,
	KEY_RCTRL,
	KEY_UPARROW,
	KEY_DOWNARROW,
	KEY_LEFTARROW,
	KEY_RIGHTARROW,
};
#endif

void SetScandouble(int sd)
{
	SPI(0xff);
	SPI_ENABLE(HW_SPI_CONF);
	SPI(UIO_BUT_SW); // Set "DIP switch" for scandoubler
	SPI(sd<<4);
	SPI_DISABLE(HW_SPI_CONF);
}


int scandouble=0;
//int prevbuttons=0;
unsigned int joy_timestamp=0;
#define JOY_REPEATDELAY 160
#define SCANDOUBLE_TIMEOUT 1000
#define LONGPRESS_TIMEOUT 750


void Menu_Run()
{
	int i;
	int upd=0;
	int press=0;
	int buttons=HW_JOY(REG_JOY_EXTRA);
	int menu_timestamp;
	struct menu_entry *m=menu;
#ifdef MENU_HOTKEYS
	struct hotkey *hk=hotkeys;
#endif
	int joy=HW_JOY(REG_JOY);

	HandlePS2RawCodes(menu_visible);

#ifdef CONFIG_JOYKEYS_TOGGLE
	while(TestKey(KEY_NUMLOCK))
	{
		HandlePS2RawCodes(menu_visible);
		press=1;
	}

	if(press)
	{
		joykeys_active=!joykeys_active;
		Menu_Message(joykeys_active ? "Joykeys on" : "Joykeys off",700);
	}
	press=0;
#endif

	menu_timestamp=GetTimer(LONGPRESS_TIMEOUT);
	while(TestKey(KEY_F12) || (buttons & JOY_BUTTON_MENU))
	{
		press=1;
		buttons=HW_JOY(REG_JOY_EXTRA);
		HandlePS2RawCodes(menu_visible);
		if(CheckTimer(menu_timestamp))
		{
			SetScandouble(scandouble^=1);
			menu_timestamp=GetTimer(LONGPRESS_TIMEOUT);
		}
	}
	if(press)
	{
		Menu_ShowHide(-1);
		TestKey(KEY_ENTER); // Swallow any enter key events if the core's not using enter for joysticks
		//		printf("Menu visible %d\n",menu_visible);
		upd=1;
	}

	if(!menu_visible)	// Swallow any keystrokes that occur while the OSD is hidden...
	{
#ifdef CONFIG_JOYKEYS
		if(joykeys_active)
		{
			int joybit=0x8000;
			unsigned char *key=joy_keymap;
			while(joybit)
			{
				if(TestKey(*key++))
					joy|=joybit;
				joybit>>=1;
			}
		}
#endif
		TestKey(KEY_PAGEUP);
		TestKey(KEY_PAGEDOWN);
		Menu_Joystick(0,joy&0xff);
		Menu_Joystick(1,joy>>8);
		return;
	}

	joy=(joy&0xff)|(joy>>8); // Merge ports;

	if(joy)
	{
		if(!CheckTimer(joy_timestamp))
			joy=0;
		else
			joy_timestamp=GetTimer(JOY_REPEATDELAY);
	}
	else
		joy_timestamp=0;

	if((joy&0x02)||(TestKey(KEY_LEFTARROW)&2))
	{
		if((m+menurows)->action)
			MENU_ACTION_CALLBACK((m+menurows)->action)(ROW_LEFT);
	}

	if((joy&0x01)||(TestKey(KEY_RIGHTARROW)&2))
	{
		if((m+menurows)->action)
			MENU_ACTION_CALLBACK((m+menurows)->action)(ROW_RIGHT);
	}

	if((joy&0x08)||(TestKey(KEY_UPARROW)&2))
	{
		if(currentrow)
			--currentrow;
		else if((m+menurows)->action)
			MENU_ACTION_CALLBACK((m+menurows)->action)(ROW_LINEUP);
		upd=1;
	}

	if((joy&0x04)||(TestKey(KEY_DOWNARROW)&2))
	{
		if(currentrow<(menurows-1))
			++currentrow;
		else if((m+menurows)->action)
			MENU_ACTION_CALLBACK((m+menurows)->action)(ROW_LINEDOWN);
		upd=1;
	}

	if(TestKey(KEY_PAGEUP)&2)
	{
		if(currentrow)
			currentrow=0;
		else if((m+menurows)->action)
			MENU_ACTION_CALLBACK((m+menurows)->action)(ROW_PAGEUP);
		upd=1;
	}

	if(TestKey(KEY_PAGEDOWN)&2)
	{
		if(currentrow<(menurows-1))
			currentrow=menurows-1;
		else if((m+menurows)->action)
			MENU_ACTION_CALLBACK((m+menurows)->action)(ROW_PAGEDOWN);
		upd=1;
	}

	// Find the currently highlighted menu item
	press=0;
	menu_longpress=0;
	menu_timestamp=GetTimer(LONGPRESS_TIMEOUT);
	while(!menu_longpress && ((joy&0xf0) || TestKey(KEY_ENTER)))
	{
		press=1;
		joy=HW_JOY(REG_JOY);
		joy=(joy&0xff)|(joy>>8); // Merge ports;
		HandlePS2RawCodes(menu_visible);
		if(CheckTimer(menu_timestamp))
			menu_longpress=1;
	}
	if(press && (m+currentrow)->action)
		MENU_ACTION_CALLBACK((m+currentrow)->action)(currentrow);

#ifdef MENU_HOTKEYS
	while(hk && hk->key)
	{
		if(TestKey(hk->key)&1)	// Currently pressed?
			hk->callback(currentrow);
		++hk;
	}
#endif

	if(upd)
		Menu_Draw(currentrow);

	if(menu_autohide && CheckTimer(menu_autohide))
	{
		Menu_Draw(currentrow);
		Menu_ShowHide(0);
		menu_autohide=0;
	}
}


void Menu_Message(char *msg,int autohide)
{
	struct menu_entry *m=menu+7;	
	char *tmp=m->label;
	if(msg)
	{
		m->label=msg;
		Menu_Set(menu); /* Draw menu, with side effect of selecting and highlighting the last row */
		m->label=tmp;
	}
	Menu_ShowHide(msg!=0);
	menu_autohide=autohide ? GetTimer(autohide) : 0;
}

