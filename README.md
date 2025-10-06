# :sparkles: XRay Vless Reality + MikroTik :sparkles:


![img](Demonstration/logo.png)

В данном репозитории рассматривается работа MikroTik RouterOS V7.20+ с протоколом **XRay Vless Reality**. В процессе настройки, относительно вашего оборудования, следует выбрать вариант реализации с [контейнером](https://help.mikrotik.com/docs/display/ROS/Container) внутри RouterOS или без контейнера. 

Предполагается что вы уже настроили серверную часть Xray например [с помощью панели управления 3x-ui](https://github.com/MHSanaei/3x-ui) и протестировали конфигурацию клиента например на смартфоне или персональном ПК.

:school: Внимание! Инструкция среднего уровня сложности. Перед применением настроек вам необходимо иметь опыт в настройке MikroTik уровня сертификации MTCNA. 

Присутствуют готовые контейнеры на [Docker Hub](https://hub.docker.com/u/gritsenko/xray-mikrotik) которые можно сразу использовать внутри RouterOS. Контейнеры делятся на три архитектуры **ARM, ARM64 и x86**.

.

------------

* [Преднастройка RouterOS](#Pre_edit)
* [Вариант №1. RouterOS с контейнером](#R_Xray_1)
	- [Сборка контейнера на Windows](#R_Xray_1_windows)
	- [Готовые контейнеры](#R_Xray_1_build_ready)
	- [Настройка контейнера в RouterOS](#R_Xray_1_settings)
* [Вариант №2. RouterOS без контейнера](#R_Xray_2)
	- [Установка Debian Linux](#R_Xray_2_installDebian)
	- [Настройка Debian](#R_Xray_2_setupDebian)
	- [Настройка конфигурации Xray](#R_Xray_2_setup)
	- [Настройка роутера](#R_Xray_2_setup_router)
	

------------

<a name='Pre_edit'></a>
## Преднастройка RouterOS

Создадим отдельную таблицу маршрутизации:
```
/routing table 
add disabled=no fib name=r_to_vpn
```
Добавим address-list "to_vpn" что бы находившиеся в нём IP адреса и подсети заворачивать в пока ещё не созданный туннель
```
/ip firewall address-list
add address=8.8.8.8 list=to_vpn
```
Добавим address-list "RFC1918" что бы не потерять доступ до RouterOS при дальнейшей настройке
```
/ip firewall address-list
add address=10.0.0.0/8 list=RFC1918
add address=172.16.0.0/12 list=RFC1918
add address=192.168.0.0/16 list=RFC1918
```

Добавим правила в mangle для address-list "RFC1918" и переместим его в самый верх правил
```
/ip firewall mangle
add action=accept chain=prerouting dst-address-list=RFC1918 in-interface-list=!WAN
```

Добавим правило транзитного трафика в mangle для address-list "to_vpn"
```
/ip firewall mangle
add action=mark-connection chain=prerouting connection-mark=no-mark dst-address-list=to_vpn in-interface-list=!WAN \
    new-connection-mark=to-vpn-conn passthrough=yes
```
Добавим правило для транзитного трафика отправляющее искать маршрут до узла назначения через таблицу маршрутизации "r_to_vpn", созданную на первом шаге
```
add action=mark-routing chain=prerouting connection-mark=to-vpn-conn in-interface-list=!WAN new-routing-mark=r_to_vpn \
    passthrough=yes
```
Маршрут по умолчанию в созданную таблицу маршрутизации "r_to_vpn" добавим чуть позже.


```
/ip firewall mangle
add action=mark-connection chain=output connection-mark=no-mark \
    dst-address-list=to_vpn new-connection-mark=to-vpn-conn-local \
    passthrough=yes
add action=mark-routing chain=output connection-mark=to-vpn-conn-local \
    new-routing-mark=r_to_vpn passthrough=yes
```

------------
<a name='R_Xray_1'></a>
<a name='R_Xray_1_windows'></a>

### Сборка контейнера на Windows

<a name='R_Xray_1_build_ready'></a>
**Где взять контейнер?** Его можно собрать самому из текущего репозитория каталога **"Containers"** или скачать готовый образ под выбранную архитектуру из [Docker Hub](https://hub.docker.com/u/gritsenko/xray-mikrotik).
Скачав готовый образ [переходим сразу к настройке](#R_Xray_1_settings).


Для самостоятельной сборки следует установить подсистему Docker [buildx](https://github.com/docker/buildx?tab=readme-ov-file), "make" и "go".

В текущем примере будем собирать на Windows:
1) Скачиваем [Docker Desktop](https://docs.docker.com/desktop/) и устанавливаем
2) Скачиваем каталог **"Containers"**
3) Открываем CMD и переходим в каталог **"Containers"** (cd <путь до каталога>)
4) Запускаем Docker с ярлыка на рабочем столе (окно приложения должно просто висеть в фоне при сборке) и через cmd собираем контейнер под выбранную архитектуру RouterOS

- ARMv8 (arm64/v8) — спецификация 8-го поколения оборудования ARM, которое поддерживает архитектуры AArch32 и AArch64.
- ARMv7 (arm/v7) — спецификация 7-го поколения оборудования ARM, которое поддерживает только архитектуру AArch32. 
- AMD64 (amd64) — это 64-битный процессор, который добавляет возможности 64-битных вычислений к архитектуре x86

Для ARMv8 (Containers\Dockerfile_arm64)
```
docker image prune -f

docker buildx build -f Dockerfile_arm64 --no-cache --progress=plain --platform linux/arm64/v8 --output=type=docker --tag user/docker-xray-vless:latest .
```

Для ARMv7 (Containers\Dockerfile_arm)
```
docker image prune -f

docker buildx build -f Dockerfile_arm --no-cache --progress=plain --platform linux/arm/v7 --output=type=docker --tag user/docker-xray-vless:latest .
```

Для amd64 (Containers\Dockerfile_amd64)
```
docker image prune -f

docker buildx build -f Dockerfile_amd64 --no-cache --progress=plain --platform linux/amd64 --output=type=docker --tag user/docker-xray-vless:latest .
```
Иногда процесс создания образа может подвиснуть из-за плохого соединения с интернетом. Следует повторно запустить сборку. 
После сборки образа вы можете загрузить контейнер в приватный репозиторий Docker HUB и продолжить настройку по [следующему пункту](#R_Xray_1_settings)



<a name='R_Xray_1_settings'></a>
### Настройка контейнера в RouterOS


**В RouterOS выполняем:**

0) Подключем Docker HUB в наш RouterOS
```
/file add type=directory name=ramstorage
```
```
/container config
set ram-high=200.0MiB registry-url=https://registry-1.docker.io tmpdir=ramstorage
```

1) Создадим интерфейс для контейнера
```
/interface veth add address=172.18.20.6/30 gateway=172.18.20.5 gateway6="" name=xray-vless
```

2) Добавим правило в mangle для изменения mss для трафика, уходящего в контейнер. Поместите его после правила с RFC1918 (его мы создали ранее).
```
/ip firewall mangle add action=change-mss chain=forward new-mss=1360 out-interface=xray-vless passthrough=yes protocol=tcp tcp-flags=syn tcp-mss=1420-65535
```

3) Назначим на созданный интерфейс IP адрес. IP 172.18.20.6 возьмёт себе контейнер, а 172.18.20.5 будет адрес RouterOS.
```
/ip address add interface=xray-vless address=172.18.20.5/30
```
4) В таблице маршрутизации "r_to_vpn" создадим маршрут по умолчанию ведущий на контейнер
```
/ip route add distance=1 dst-address=0.0.0.0/0 gateway=172.18.20.6 routing-table=r_to_vpn
```
5) Включаем masquerade для всего трафика, уходящего в контейнер.
```
/ip firewall nat add action=masquerade chain=srcnat out-interface=xray-vless
```
6) Создадим переменные окружения envs под названием "xvr", которые позже при запуске будем передавать в контейнер.
Параметры подключения Xray Vless вы должны взять из сервера панели 3x-ui. 

:anger: Пример импортируемой строки из 3x-ui раздела клиента "Details" (у вас настройки должны быть сгенерированы свои):
```
vless://e3203dfe-9s62-4de5-bf9b-ecd36c9af225@myhost.com:443?type=tcp&security=reality&pbk=fTndnleCTkK9_jtpwCAdxtEwJUkQ22oY1W8dTza2xHs&fp=chrome&sni=apple.com&sid=29d2d3d5a398&spx=%2wF#d
```
Размещаем данные параметры для передачи в контейнер
```
/container envs
add key=SERVER_ADDRESS    name=xvr value=myhost.com
add key=SERVER_PORT       name=xvr value=443
add key=USER_ID           name=xvr value=e3203dfe-9s62-4de5-bf9b-ecd36c9af225
add key=ENCRYPTION        name=xvr value=none
add key=FINGERPRINT_FP    name=xvr value=chrome
add key=SERVER_NAME_SNI   name=xvr value=apple.com
add key=PUBLIC_KEY_PBK    name=xvr value=fTndnleCTkK9_jtpwCAdxtEwJUkQ22oY1W8dTza2xHs
add key=SHORT_ID_SID      name=xvr value=29d2d3d5a398
add key=TZ                list=xvr value=Europe/Moscow
```

7) Теперь создадим сам контейнер. Здесь вам нужно выбрать репозиторий из [Docker Hub](https://hub.docker.com/r/gritsenko/xray-mikrotik) с архитектурой под ваше устройство.


```
/container/add remote-image=gritsenko/xray-mikrotik:arm64 hostname=xray-vless interface=xray-vless logging=no start-on-boot=yes envlist=xvr root-dir=/docker/container-xray-mikrotik dns=172.18.20.5
```
Подождите немного пока контейнер распакуется до конца. В итоге у вас должна получиться похожая картина, в которой есть распакованный контейнер и окружение envs. Если в процессе импорта возникают ошибки, внимательно читайте лог из RouterOS.

![img](Demonstration/1.1.png)

![img](Demonstration/1.2.png)

:anger:
Контейнер будет использовать только локальный DNS сервер на IP адресе 172.18.20.5. Необходимо разрешить DNS запросы TCP/UDP порт 53 на данный IP в правилах RouterOS в разделе ```/ip firewall filter```

8) Запускаем контейнер через WinBox в разделе меню Winbox "container". В логах MikroTik вы увидите характерные сообщения о запуске контейнера. 

 



[Donate :sparkling_heart:](https://telegra.ph/Youre-making-the-world-a-better-place-01-14)


