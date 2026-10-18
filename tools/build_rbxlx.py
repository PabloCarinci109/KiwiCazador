#!/usr/bin/env python3
"""
build_rbxlx.py -- Genera KiwiCazador.rbxlx a partir de los fuentes en src/.

Uso:
    python3 tools/build_rbxlx.py

El .rbxlx resultante es un lugar de Roblox (un solo archivo) con todos
los scripts adentro: se abre directo en Roblox Studio con
File > Open from File... y se publica con File > Publish to Roblox.
"""

from pathlib import Path
import os
import xml.etree.ElementTree as ET

RAIZ = Path(__file__).resolve().parent.parent
SRC = RAIZ / "src"
SALIDA = Path(os.environ.get("KIWI_OUT", str(RAIZ / "KiwiCazador.rbxlx")))


class Referencias:
    """Generador de referents unicos para el XML."""

    def __init__(self):
        self.numero = 0

    def nuevo(self):
        ref = "RBX%03d" % self.numero
        self.numero += 1
        return ref


refs = Referencias()


def item(padre, clase, nombre):
    el = ET.SubElement(padre, "Item", {"class": clase, "referent": refs.nuevo()})
    props = ET.SubElement(el, "Properties")
    ET.SubElement(props, "string", {"name": "Name"}).text = nombre
    return el, props


def agregar_fuente(padre, clase, nombre, ruta):
    el, props = item(padre, clase, nombre)
    ET.SubElement(props, "ProtectedString", {"name": "Source"}).text = ruta.read_text(encoding="utf-8")
    return el


def agregar_bool(props, nombre, valor):
    ET.SubElement(props, "bool", {"name": nombre}).text = "true" if valor else "false"


def agregar_float(props, nombre, valor):
    ET.SubElement(props, "float", {"name": nombre}).text = str(valor)


def agregar_token(props, nombre, valor):
    ET.SubElement(props, "token", {"name": nombre}).text = str(valor)


def construir():
    raiz = ET.Element("roblox", {
        "xmlns:xmime": "http://www.w3.org/2005/05/xmlmime",
        "xmlns:xsi": "http://www.w3.org/2001/XMLSchema-instance",
        "xsi:noNamespaceSchemaLocation": "http://www.roblox.com/roblox.xsd",
        "version": "4",
    })
    ET.SubElement(raiz, "External").text = "null"
    ET.SubElement(raiz, "External").text = "nil"

    # Workspace: sin Streaming (el mapa se genera por codigo)
    _, props = item(raiz, "Workspace", "Workspace")
    agregar_bool(props, "StreamingEnabled", False)

    # Lighting: tecnologia ShadowMap (3)
    _, props = item(raiz, "Lighting", "Lighting")
    agregar_token(props, "Technology", 3)

    # SoundService
    _, props = item(raiz, "SoundService", "SoundService")
    agregar_bool(props, "RespectFilteringEnabled", True)

    # ReplicatedStorage.KiwiShared
    replicated, _ = item(raiz, "ReplicatedStorage", "ReplicatedStorage")
    compartida, _ = item(replicated, "Folder", "KiwiShared")
    for nombre in ("Config", "Util", "Net"):
        agregar_fuente(compartida, "ModuleScript", nombre, SRC / "shared" / (nombre + ".lua"))

    # ServerScriptService.KiwiServer
    servicio_srv, _ = item(raiz, "ServerScriptService", "ServerScriptService")
    servidor, _ = item(servicio_srv, "Folder", "KiwiServer")
    agregar_fuente(servidor, "Script", "Main", SRC / "server" / "Main.server.lua")
    if os.environ.get("KIWI_AUTOTEST"):
        agregar_fuente(servidor, "Script", "AutoTest", SRC / "server" / "AutoTest.server.lua")
    modulos_srv, _ = item(servidor, "Folder", "modules")
    for nombre in ("Shared", "WorldBuilder", "KiwiModel", "KiwiController",
                   "ToolService", "Actions", "Weather", "GameManager",
                   "Destruction"):
        agregar_fuente(modulos_srv, "ModuleScript", nombre, SRC / "server" / "modules" / (nombre + ".lua"))

    # StarterPlayer.StarterPlayerScripts.KiwiClient
    starter, props = item(raiz, "StarterPlayer", "StarterPlayer")
    agregar_float(props, "CharacterWalkSpeed", 16)
    agregar_bool(props, "EnableMouseLockOption", True)
    scripts_jugador, _ = item(starter, "StarterPlayerScripts", "StarterPlayerScripts")
    cliente, _ = item(scripts_jugador, "Folder", "KiwiClient")
    agregar_fuente(cliente, "LocalScript", "Main", SRC / "client" / "Main.client.lua")
    modulos_cli, _ = item(cliente, "Folder", "modules")
    agregar_fuente(modulos_cli, "ModuleScript", "HUD", SRC / "client" / "modules" / "HUD.lua")
    agregar_fuente(modulos_cli, "ModuleScript", "ViewModel", SRC / "client" / "modules" / "ViewModel.lua")
    agregar_fuente(modulos_cli, "ModuleScript", "WeatherFX", SRC / "client" / "modules" / "WeatherFX.lua")

    return raiz


def main():
    raiz = construir()
    ET.indent(raiz, space="\t")
    xml = '<?xml version="1.0" encoding="utf-8"?>\n' + ET.tostring(raiz, encoding="unicode") + "\n"
    SALIDA.write_text(xml, encoding="utf-8")

    total = sum(1 for _ in raiz.iter("Item"))
    scripts = sum(1 for el in raiz.iter("Item")
                  if el.get("class") in ("Script", "LocalScript", "ModuleScript"))
    print("Listo: %s" % SALIDA)
    print("Items: %d (%d scripts), tamano: %.1f KB" % (total, scripts, SALIDA.stat().st_size / 1024))


if __name__ == "__main__":
    main()
