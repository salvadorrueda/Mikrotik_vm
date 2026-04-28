# Mikrotik_vm
Scripts per configurar una router Mikrotik en una màquina virtual de VirtualBox.

Adreça del repositori: https://github.com/salvadorrueda/Mikrotik_vm.git 

Aquest repsitori està pensat per automatitzar la tasca de configurar una màquina virtual de VirtualBox com a router.

Al repositori tenim dos scripts. Un script que descarrega, importa i configura la màquina virtual de VirtualBox. També hi ha un segon script que configura el Mikrotik.

Més concretament els passos que ha de seguir cada scrip són:
Shell Script de la Màquina virtual de Mikrotik
 
Descarregar la .ova de Mikrotik. A dia dimarts, 28 d'abril de 2026 la CHR longTerm és la versió 7.21.4 i es pot descarregar de  https://download.mikrotik.com/routeros/7.21.4/chr-7.21.4.ova 

Importar la .ova

Canviar el nom de la màquina que per defecte és mv a "m00".

Afegir una nova interfície de xarxa perquè la .ova només en té una i configurar-la en xarxa interna amb el nom de la xarxa interna "m00". Aquesta interfície de xarxa serà la LAN.


Un cop importada i configurada la màquina virtual Mikrotik "m00". Cal iniciar-la per poder configurar el Mikrotik.

Mikrotik configura la primera interficie de xarxa amb DHCP. Així que aquesta adreça pot ser qualsevol dins del rang de la xarxa. 
Per identificar quina és l'adreça IP de la màquina virtual Mikrotik podem fer un nmap abans i després d'iniciar la màquina per veure si ha aparegut una nova màquina que correspongui a l'adreça física (MAC ADDRESS) de la màquina virtual Mikrotik.

 
El més fàcil per automatizar la configuració de la màquina virtual Mikrotik crec que és crear scripts de Mikrotik .rsc i executar-los per ssh. Connectar-se per ssh i executar directament les comandes també és una bona opció.

El  primer cop que et valides com a usuari "admin" cal especificar un nou password. 

Les tasques ha realitzar en la configuració de la màquina virtual de Mikrotik són:
Canvi del nom del sistema que ha de ser "m00".
Crear un nou usuari "salvadorrueda" amb tots els permisos i sense password perquè l'usuari utilitzarà claus ssh per connectar-se.
Configurar l'accés mitjançant claus ssh a l'usuari "salvadorrueda". Copiant la pública RSA de l'úsuari que executa el script (~/.ssh/id_rsa.pub) o la clau ed25519 (~/.ssh/id_ed25519.pub) si no existeix cap de les dues s'hauria de preguntar a l'usuari que especifiqui la ubicació de les claus o si en vol crear-ne de noves.
 
Deshabilitar la compta d'admin.

Canviar el port per defecte del ssh al 2222
Deshabilitar tots els serveis d'accés llevat el ssh. 
Configurar per a que el servei ssh només estigui actiu durant els primers 10 minuts després d'iniciar el router Mikrotik.









