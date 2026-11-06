# :sparkles: XRay Vless Reality + MikroTik :sparkles:


![img](Demonstration/logo.png)

:dizzy: Аналог [AmneziaWG + MikroTik](https://github.com/catesin/AmneziaWG-MikroTik)


В данном репозитории рассматривается работа MikroTik RouterOS V7.26.4+ с протоколом **XRay Vless Reality**. В процессе настройки, относительно вашего оборудования, следует выбрать вариант реализации с [контейнером](https://manual.mikrotik.com/docs/containers/) внутри RouterOS или без контейнера. 

Предполагается что вы уже настроили серверную часть Xray например [с помощью панели управления 3x-ui](https://github.com/MHSanaei/3x-ui) и протестировали конфигурацию клиента, например на смартфоне или персональном ПК.

:school: Внимание! Инструкция среднего уровня сложности. Перед применением настроек вам необходимо иметь опыт в настройке MikroTik уровня сертификации MTCNA. 

В репозитории присутствует инструкция с [готовыми](https://hub.docker.com/u/catesin) контейнерами и шаблоны для самостоятельной сборки в каталоге **"Containers"**. Контейнеры делятся на три архитектуры **ARM, ARM64 и x86**.

Вариант №2 без контейнера подойдёт к любому домашнему роутеру который хоть немного умеет работать с аналогичными в MikroTik адрес-листами или имеет расширенный функционал по маршрутизации.

------------

* [Преднастройка RouterOS](#Pre_edit)
* [Вариант №1. RouterOS с контейнером](#R_Xray_1)
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
:warning: Отключите **FastTrack** в RouterOS.

Создадим отдельную таблицу маршрутизации:
```
/routing table 
add disabled=no fib name=r_to_vpn
```
Добавим address-list "to_vpn" что бы находившиеся в нём IP адреса и подсети заворачивать в пока ещё не созданный туннель
```
/ip firewall address-list
add address=172.217.168.206 list=to_vpn
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

:exclamation:Два выше обозначенных правила будут работать только для трафика, проходящего через маршрутизатор. 
Если вы хотите заворачивать трафик, генерируемый самим роутером (например команда ping 172.217.168.206 c роутера для проверки туннеля в контейнере), тогда добавляем ещё два правила (не обязательно). 
Они должны находиться по порядку, следуя за вышеобозначенными правилами.
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
## Вариант №1. RouterOS с контейнером

### RouterOS с контейнером

Данный пункт настройки подходит только для устройств с архитектурой **ARM, ARM64 или x86**. 
Перед запуском контейнера в RouteOS убедитесь что у вас [включены контейнеры](https://help.mikrotik.com/docs/spaces/ROS/pages/84901929/Container). 
С полным списком поддерживаемых устройств можно ознакомится [тут](https://mikrotik.com/products/matrix). 

:warning: Предполагается что на устройстве (или если есть USB порт с флешкой) имеется +- 40 Мбайт свободного места для разворачивания контейнера внутри RouterOS. Сам контейнер весит не более 30 Мбайт. Если места не хватает, его можно временно расширить [за счёт оперативной памяти](https://help.mikrotik.com/docs/spaces/ROS/pages/91193346/Disks#Disks-AllocateRAMtofolder). После перезагрузки RouterOS, всё что находится в RAM, стирается. 

### Включение функции контейнеров в RouterOS

Основная инструкция по включению функции контейнеров находится [ТУТ](https://help.mikrotik.com/docs/spaces/ROS/pages/84901929/Container#Container-Summary) или [ТУТ](https://www.google.com/search?q=%D0%9A%D0%B0%D0%BA+%D0%B2%D0%BA%D0%BB%D1%8E%D1%87%D0%B8%D1%82%D1%8C+%D0%BA%D0%BE%D0%BD%D1%82%D0%B5%D0%B9%D0%BD%D0%B5%D1%80%D1%8B+%D0%B2+mikrotik&oq=%D0%BA%D0%B0%D0%BA+%D0%B2%D0%BA%D0%BB%D1%8E%D1%87%D0%B8%D1%82%D1%8C+%D0%BA%D0%BE%D0%BD%D1%82%D0%B5%D0%B9%D0%BD%D0%B5%D1%80%D1%8B+%D0%B2+mikrotik)

Порядок действий выглядит так: 

* Обновляемся до последней версии RouterOS
* Скачиваем дополнительный пакет из расширений "all packages" на [официальном сайте](https://mikrotik.com/download)
* Устанавливаем пакет
* Включаем функцию контейнеров

<a name='R_Xray_1_build_ready'></a>
### Готовые контейнеры

**Где взять контейнер?** Его можно собрать самому из текущего репозитория каталога **"Containers"** или скачать готовый образ под выбранную архитектуру из [Docker Hub](https://hub.docker.com/u/catesin).
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

В текущем примере на устройстве MikroTik флешки нет. Хранить будем всё в корне.
Если у вас есть USB порт и флешка, лучше размещать контейнер на ней.  Можно комбинировать память загрузив контейнер в расшаренный диск [за счёт оперативной памяти](https://www.youtube.com/watch?v=uZKTqRtXu4M), а сам контейнер разворачивать в постоянной памяти.

Рекомендую создать пространство из ОЗУ хотя бы для tmp директории. Размер регулируйте самостоятельно:
```
/disk
add slot=ramstorage tmpfs-max-size=100M type=tmpfs
```

:exclamation:**Если контейнер не запускается на флешке.**
Например, вы хотите разместить контейнер в каталоге /usb1/docker/xray. Не создавайте заранее каталог xray на USB-флеш-накопителе. При создании контейнера добавьте в команду распаковки параметр "root-dir=usb1/docker/xray", в этом случае контейнер распакуется самостоятельно создав каталог /usb1/docker/xray и запустится без проблем.

**В RouterOS выполняем:**

0) Подключим Docker HUB в наш RouterOS

```
/container config set tmpdir=ramstorage

/container/config/set registry-url=https://registry-1.docker.io tmpdir=/ramstorage
```

1) Создадим интерфейс для контейнера
```
/interface veth add address=172.18.20.6/30 gateway=172.18.20.5 gateway6="" name=docker-xray-vless-veth
```

2) Добавим правило в mangle для изменения mss для трафика, уходящего в контейнер. Поместите его после правила с RFC1918 (его мы создали ранее).
```
/ip firewall mangle add action=change-mss chain=forward new-mss=1360 out-interface=docker-xray-vless-veth passthrough=yes protocol=tcp tcp-flags=syn tcp-mss=1420-65535
```

3) Назначим на созданный интерфейс IP адрес. IP 172.18.20.6 возьмёт себе контейнер, а 172.18.20.5 будет адрес RouterOS.
```
/ip address add interface=docker-xray-vless-veth address=172.18.20.5/30
```
4) В таблице маршрутизации "r_to_vpn" создадим маршрут по умолчанию ведущий на контейнер
```
/ip route add distance=1 dst-address=0.0.0.0/0 gateway=172.18.20.6 routing-table=r_to_vpn
```
5) Включаем masquerade для всего трафика, уходящего в контейнер.
```
/ip firewall nat add action=masquerade chain=srcnat out-interface=docker-xray-vless-veth
```
6) Создадим переменные окружения envs под названием "xvr", которые позже при запуске будем передавать в контейнер.
Параметры подключения Xray Vless вы должны взять из сервера панели 3x-ui. 

:anger: Пример импортируемой строки из 3x-ui раздела клиента "Details" (у вас настройки должны быть сгенерированы свои):
```
vless://62878542-8f68-42f0-8c66-e5a46e9c2cb1@mydomain.com:443?type=tcp&encryption=none&security=reality&pbk=7JTFIDt3Eyihq723jpp564DnK8X_GHLs_jHjLrRMFng&fp=randomized&sni=google.com&sid=aeb4c72f73a05af2&spx=%2F&flow=xtls-rprx-vision#4xg43kggm
```
Размещаем данные параметры для передачи в контейнер


|   **Переменная**   |             **Пример значения**             | **Пояснение**                                    |
| :----------------: | :-----------------------------------------: | :----------------------------------------------- |
| **SERVER_ADDRESS** |             mydomain.com                    | Адрес Xray сервера                               |
|   **SERVER_PORT**  |                     443                     | Порт сервера                                     |
|       **ID**       |     62878542-8f68-42f0-8c66-e5a46e9c2cb1    | UUID клиента VLESS                               |
|   **ENCRYPTION**   |                     none                    | Для VLESS всегда `none`                          |
|     **NETWORK**    |                   tcp                       | Stream для Xray (tcp(RAW),XHTTP)/ другие)        |
|      **FLOW**      |               xtls-rprx-vision              | Flow для Xray (Vision / другие)                  |
|       **FP**       |                    randomized               | Fingerprint REALITY (браузерная маскировка)      |
|       **SNI**      |                  google.com                 | SNI для TLS / REALITY                            |
|       **PBK**      | 7JTFIDt3Eyihq723jpp564DnK8X_GHLs_jHjLrRMFng | Публичный ключ REALITY                           |
|       **SID**      |               aeb4c72f73a05af2              | ShortId REALITY                                  |
|       **SPX**      |                      /                      | Путь SpiderX для REALITY                         |

```
/container envs
add key=SERVER_ADDRESS list=xvr value=mydomain.com
add key=SERVER_PORT list=xvr value=443
add key=ID list=xvr value=62878542-8f68-42f0-8c66-e5a46e9c2cb1
add key=ENCRYPTION list=xvr value=none
add key=NETWORK list=xvr value=tcp
add key=FLOW list=xvr value=xtls-rprx-vision
add key=FP list=xvr value=randomized
add key=SNI list=xvr value=google.com
add key=PBK list=xvr value=7JTFIDt3Eyihq723jpp564DnK8X_GHLs_jHjLrRMFng
add key=SID list=xvr value=aeb4c72f73a05af2
add key=SPX list=xvr value=/
```

7) Теперь создадим сам контейнер. Здесь вам нужно выбрать репозиторий из [Docker Hub](https://hub.docker.com/u/catesin) с архитектурой под ваше устройство или скачать контейнер локально с репозитория, поместив его в каталог на RouterOS. Не создавайте заранее каталог для параметра "root-dir"

*  Для ARMv7 (arm)
```
/container add hostname=xray-vless interface=docker-xray-vless-veth envlist=xvr root-dir=xray-vless logging=yes start-on-boot=yes remote-image=catesin/xray-mikrotik-arm:latest
```

* Для ARMv8 (arm64)
```
/container add hostname=xray-vless interface=docker-xray-vless-veth envlist=xvr root-dir=xray-vless logging=yes start-on-boot=yes remote-image=catesin/xray-mikrotik-arm64:latest
```

* Для amd64

```
/container add hostname=xray-vless interface=docker-xray-vless-veth envlist=xvr root-dir=xray-vless logging=yes start-on-boot=yes remote-image=catesin/xray-mikrotik-amd64:latest
```

Отредактируйте местоположение контейнера в ```root-dir``` при необходимости.

Подождите немного пока контейнер распакуется до конца. В итоге у вас должна получиться похожая картина, в которой есть распакованный контейнер и окружение envs. Если в процессе импорта возникают ошибки, внимательно читайте лог из RouterOS.

![img](Demonstration/1.1.png)

![img](Demonstration/1.2.png)

![img](Demonstration/1.3.png)

:anger:
Контейнер будет использовать только локальный DNS сервер на IP адресе шлюза, коим для него будет адрес роутера 172.18.20.5. Необходимо разрешить DNS запросы TCP/UDP порт 53 на данный IP в правилах RouterOS в разделе ```/ip firewall filter```
Указанные правила должны быть выше запрещающих. 
```
/ip firewall filter
add chain=input in-interface=docker-xray-vless-veth src-address=172.18.20.6 dst-address=172.18.20.5 protocol=udp dst-port=53 action=accept comment="container -> local DNS (UDP/53)"
add chain=input in-interface=docker-xray-vless-veth src-address=172.18.20.6 dst-address=172.18.20.5 protocol=tcp dst-port=53 action=accept comment="container -> local DNS (TCP/53)"
```

8) Запускаем контейнер через WinBox в разделе меню Winbox "container". В логах MikroTik вы увидите характерные сообщения о запуске контейнера. 

:fire::fire::fire: Поздравляю! Настройка завершена. Можно проверить доступность IP 172.217.168.206 из списка "to_vpn" (этот адрес мы добавили ранее). Проверям доступность через запрос на https порт (запрос в браузере, telnet или TNC PowerShell)
 
По желанию логирование контейнера можно отключить что бы не засорялся лог RouteOS.

------------
<a name='R_Xray_2'></a>
## Вариант №2. RouterOS без контейнера

Не известно введут ли разработчики MikroTik возможность нативной интеграции с Xray. 
Вполне вероятно, что этого может не произойти. Если вам не повезло и ваш MikroTik не поддерживает контейнеры, не расстраивайтесь. 
Есть вполне рабочее решение, подходящее большинству роутеров (не только MikroTik). 
Нам нужен [дополнительный мини ПК](https://www.google.com/search?q=%D0%BC%D0%B8%D0%BD%D0%B8+%D0%BF%D0%BA+%D0%B4%D0%BB%D1%8F+linux) с одним сетевым портом и возможностью установить на него [Debian Linux](https://www.debian.org/).
Идея заключается в единоразовой настройке Debian с помощью экрана монитора с клавиатурой и последующее удалённое управление без необходимости подключения периферийных устройств.  

<a name='R_Xray_2_installDebian'></a>
### Установка Debian Linux

Предполагается, что вы сможете самостоятельно установить Debian на мини ПК через GUI с редактированием некоторых значений в процессе установки, подключением кабеля ethernet к локальной сети вашего роутера.
В настройках BIOS мини ПК желательно сделать автозапуск системы при появлении питания.
Установка Debian Linux потребуется в самой минимальной конфигурации

![img](Demonstration/2.1.png)

На этапе выбора программного обеспечения устанавливаем SSH сервер и стандартные системные утилиты. 

![img](Demonstration/2.2.png)

Дальнейшие действия можно сделать, подключившись через SSH к мини ПК.

Дадим root доступ для нашего пользователя (у вас он может быть другим)

```
su -
sudo usermod -aG sudo root-home
```

P.S. По вкусу можно установить ```apt install mc htop -y```


<a name='R_Xray_2_setupDebian'></a>
### Включение маршрутизации в Linux

Маршрутизация нам необходима, так-как нужно передавать пакеты от роутера через Debian в tun2socks адаптер и далее в прокси Xray.
Фактически наш Debian будет ещё одним роутером, транслирующим передачу пакетов в socks прокси Xray.

Открываем файл
```
nano /etc/sysctl.conf
```

Ищем строку ```net.ipv4.ip_forward=```, раскомментируем и приводим к виду ```net.ipv4.ip_forward=1```. Сохраняем файл и перезагружаемся. 
Проверяем результат выполнив

```
sysctl net.ipv4.ip_forward
```

Должен получиться вывод ```net.ipv4.ip_forward = 1```


### Установка Xray

Для установки Xray прокси скачайте готовый бинарник в архиве под вашу архитектуру (скорее всего это будет Linux x64) процессора из [текущего репозитория](https://github.com/XTLS/Xray-core/releases/) распаковав архив в каталог ```/opt/xray/```

```
mkdir /opt/xray/
mkdir /opt/xray/config/
```


![img](Demonstration/2.3.png)

В каталог ```/opt/xray/config/``` чуть позже положим конфиг

### Установка tun2socks

tun2socks будет переадресовывать весть входящий трафик от физического интерфейса Linux в виртуальный "tun0" адаптер, направленный на Xray soscks прокси.
Для установки tun2socks скачайте готовый бинарник в архиве под вашу архитектуру (скорее всего это будет Linux x64) процессора из [текущего репозитория](https://github.com/xjasonlyu/tun2socks/releases/) распаковав архив в каталог ```/opt/tun2socks/```

```
mkdir /opt/tun2socks/
```

![img](Demonstration/2.4.png)


<a name='R_Xray_2_setup'></a>
### Подготовка скрипта start.sh

Для простоты настройки, создадим в каталоге ```/opt/``` исполняемый скрипт "start.sh" который будет запускать всю цепочку редактирования маршрутизации, Xray proxy и tun2socks адаптер.
Сделаем файл исполняемым.

```
nano /opt/start.sh
```

В содержимое скрипта подставьте конфигурацию клиента для Xray из 3x-ui заполнив следующие переменные. 

|   **Переменная**   |             **Пример значения**             | **Пояснение**                                    |
| :----------------: | :-----------------------------------------: | :----------------------------------------------- |
| **SERVER_ADDRESS** |             mydomain.com                    | Адрес Xray сервера                               |
|   **SERVER_PORT**  |                     443                     | Порт сервера                                     |
|       **ID**       |     62878542-8f68-42f0-8c66-e5a46e9c2cb1    | UUID клиента VLESS                               |
|   **ENCRYPTION**   |                     none                    | Для VLESS всегда `none`                          |
|      **FLOW**      |               xtls-rprx-vision              | Flow для Xray (Vision / другие)                  |
|     **NETWORK**    |                   tcp                       | Stream для Xray (tcp(RAW),XHTTP)/ другие)        |
|       **FP**       |                    randomized               | Fingerprint REALITY (браузерная маскировка)      |
|       **SNI**      |                  google.com                 | SNI для TLS / REALITY                            |
|       **PBK**      | 7JTFIDt3Eyihq723jpp564DnK8X_GHLs_jHjLrRMFng | Публичный ключ REALITY                           |
|       **SID**      |               aeb4c72f73a05af2              | ShortId REALITY                                  |
|       **SPX**      |                      /                      | Путь SpiderX для REALITY                         |

```
#!/bin/sh
echo "Starting setup Linux please wait"
pkill xray
pkill tun2socks
sleep 2

# Заполните данные переменные из конфигурации клиента для Xray 3x-ui
SERVER_ADDRESS=***
SERVER_PORT=***
ID=***
ENCRYPTION=***
FLOW=***
NETWORK=***
FP=***
SNI=***
PBK=***
SID=***
SPX=***

CONTAINER_BRIDGE_IP=$(ip route | grep default | awk '{print $3}')
echo "Setup Linux DNS please wait"
rm -f /etc/resolv.conf
tee -a /etc/resolv.conf <<< "nameserver "$CONTAINER_BRIDGE_IP""

sleep 1

SERVER_IP_ADDRESS=$(ping -c 1 $SERVER_ADDRESS | awk -F'[()]' '{print $2}')
NET_IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -vE 'lo|tun' | head -n1 | cut -d'@' -f1)


echo "SERVER_ADDRESS: $SERVER_ADDRESS"
echo "SERVER_IP_ADDRESS: $SERVER_IP_ADDRESS"
echo "NET_IFACE: $NET_IFACE"
echo "CONTAINER_BRIDGE_IP: $CONTAINER_BRIDGE_IP"

sleep 1

if [ -z "$SERVER_IP_ADDRESS" ]; then
  echo "Failed to obtain an IP address for FQDN $SERVER_ADDRESS"
  exit 1
fi

# Сетевые настройки
ip tuntap del mode tun dev tun0
ip tuntap add mode tun dev tun0
ip addr add 172.31.200.10/30 dev tun0
ip link set dev tun0 up
ip route del default via $CONTAINER_BRIDGE_IP
ip route add default via 172.31.200.10
ip route add $SERVER_IP_ADDRESS/32 via $CONTAINER_BRIDGE_IP
ip route add 1.0.0.1/32 via $CONTAINER_BRIDGE_IP
ip route add 8.8.4.4/32 via $CONTAINER_BRIDGE_IP
ip route add 192.168.0.0/16 via $CONTAINER_BRIDGE_IP
ip route add 10.0.0.0/8 via $CONTAINER_BRIDGE_IP
ip route add 172.16.0.0/12 via $CONTAINER_BRIDGE_IP


# Генерация конфигурации для Xray
cat <<EOF > /opt/xray/config/config.json
{
  "log": {
    "loglevel": "silent"
  },
  "inbounds": [
    {
      "port": 10800,
      "listen": "0.0.0.0",
      "protocol": "socks",
      "settings": {
        "udp": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
		"routeOnly": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
	  "tag": "vless-reality",
      "settings": {
        "vnext": [
          {
            "address": "$SERVER_ADDRESS",
            "port": $SERVER_PORT,
            "users": [
              {
                "id": "$ID",
                "encryption": "$ENCRYPTION",
                "flow": "$FLOW"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "$NETWORK",
        "security": "reality",
        "realitySettings": {
          "fingerprint": "$FP",
          "serverName": "$SNI",
          "publicKey": "$PBK",
          "shortId": "$SID",
		      "spx": "$SPX"
        }
      }
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": []
  }
}
EOF
echo "Start Xray core"
/opt/xray/xray run -config /opt/xray/config/config.json &
echo "Start tun2socks"
/opt/tun2socks/tun2socks -loglevel silent -tcp-sndbuf 3m -tcp-rcvbuf 3m -device tun0 -proxy socks5://127.0.0.1:10800 -interface $NET_IFACE &
echo "Linux customization is complete"
```

Сохраняем и делаем файл исполняемым

```
chmod +x /opt/start.sh
/bin/bash /opt/start.sh
```
Запускаем скрипт

<a name='R_Xray_2_setup_router'></a>
### Настройка роутера

Теперь нам остаётся завернуть нужный трафик на IP адрес Debian в локальной сети. 

Для MikroTik. В таблице маршрутизации "r_to_vpn" создадим маршрут по умолчанию ведущий на Debian и правило MASQUERADE для локальных сетей

```
/ip route
add distance=1 dst-address=0.0.0.0/0 gateway=<ip адрес Debian в локальной сети> routing-table=r_to_vpn

/ip firewall nat
add action=masquerade chain=srcnat routing-mark=r_to_vpn
```
:fire::fire::fire: Поздравляю! Настройка завершена. Можно проверить доступность IP 172.217.168.206 из списка "to_vpn" (этот адрес мы добавили ранее). Трафик должен уходить на Debian.
IP адреса назначения, которые MikroTik завернёт в Xray, будут отправляться на Debian, а он в свою очередь завернёт трафик на виртуальный tun0 адаптер, который адресует весь трафик в socks proxy Xray.

[Donate :sparkling_heart:](https://telegra.ph/Youre-making-the-world-a-better-place-01-14)


