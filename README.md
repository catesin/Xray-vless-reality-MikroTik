# :sparkles: XRay Vless Reality + MikroTik :sparkles:


![img](Demonstration/logo.png)

В данном репозитории рассматривается работа MikroTik RouterOS V7.20+ с протоколом **XRay Vless Reality**. В процессе настройки, относительно вашего оборудования, следует выбрать вариант реализации с [контейнером](https://help.mikrotik.com/docs/display/ROS/Container) внутри RouterOS или без контейнера. 

Предполагается что вы уже настроили серверную часть Xray например [с помощью панели управления 3x-ui](https://github.com/MHSanaei/3x-ui) и протестировали конфигурацию клиента например на смартфоне или персональном ПК.

:school: Внимание! Инструкция среднего уровня сложности. Перед применением настроек вам необходимо иметь опыт в настройке MikroTik уровня сертификации MTCNA. 

Присутствуют готовые контейнеры на [Docker Hub](https://hub.docker.com/u/gritsenko/xray-mikrotik) которые можно сразу использовать внутри RouterOS. Контейнеры делятся на три архитектуры **ARM, ARM64 и x86**.

Вариант №2 без контейнера подойдёт к любому домашнему роутеру который хоть немного умеет работать с аналогичными в MikroTik адрес-листами или имеет расширенный функционал по маршрутизации.

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

:exclamation:Два выше обозначенных правила будут работать только для трафика, проходящего через маршрутизатор. 
Если вы хотите заворачивать трафик, генерируемый самим роутером (например команда ping 8.8.8.8 c роутера для проверки туннеля в контейнере), тогда добавляем ещё два правила (не обязательно). 
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
<a name='R_Xray_1_windows'></a>
## Вариант №1. RouterOS с контейнером

### Сборка контейнера на Windows

Данный пункт настройки подходит только для устройств с архитектурой **ARM, ARM64 или x86**. Перед запуском контейнера в RouteOS убедитесь что у вас [включены контейнеры](https://help.mikrotik.com/docs/display/ROS/Container).  С полным списком устройств можно ознакомится [тут](https://mikrotik.com/products/matrix). [Включаем поддержку контейнеров в RouterOS](https://www.google.com/search?q=%D0%9A%D0%B0%D0%BA+%D0%B2%D0%BA%D0%BB%D1%8E%D1%87%D0%B8%D1%82%D1%8C+%D0%BA%D0%BE%D0%BD%D1%82%D0%B5%D0%B9%D0%BD%D0%B5%D1%80%D1%8B+%D0%B2+mikrotik&oq=%D0%BA%D0%B0%D0%BA+%D0%B2%D0%BA%D0%BB%D1%8E%D1%87%D0%B8%D1%82%D1%8C+%D0%BA%D0%BE%D0%BD%D1%82%D0%B5%D0%B9%D0%BD%D0%B5%D1%80%D1%8B+%D0%B2+mikrotik).
Так же предполагается что на устройстве (или если есть USB порт с флешкой) имеется +- 50 Мбайт свободного места для разворачивания контейнера внутри RouterOS и +- 150 Мбайт в оперативной памяти. Если места в storage не хватает, его можно временно расширить [за счёт оперативной памяти](https://www.youtube.com/watch?v=uZKTqRtXu4M). После перезагрузки RouterOS, всё что находится в RAM, стирается. 

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

В текущем примере на устройстве MikroTik флешки нет. Хранить будем всё с использованием расшаренного storage через оперативную память.
Если у вас есть USB порт и флешка, лучше размещать контейнер на ней.  Можно комбинировать память загрузив контейнер в расшаренный диск [за счёт оперативной памяти](https://www.youtube.com/watch?v=uZKTqRtXu4M), а сам контейнер разворачивать в постоянной памяти.

Рекомендую создать пространство из ОЗУ хотя бы для tmp директории. Размер регулируйте самостоятельно:
```
/disk
add slot=ramstorage tmpfs-max-size=100M type=tmpfs
```

:exclamation:**Если контейнер не запускается на флешке.**
Например, вы хотите разместить контейнер в каталоге /usb1/docker/xray. Не создавайте заранее каталог xray на USB-флеш-накопителе. При создании контейнера добавьте в команду распаковки параметр "root-dir=usb1/docker/xray", в этом случае контейнер распакуется самостоятельно создав каталог /usb1/docker/xray и запустится без проблем.

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
add key=SERVER_ADDRESS list=xvr value=myhost.com
add key=SERVER_PORT list=xvr value=443
add key=USER_ID list=xvr value=e3203dfe-9s62-4de5-bf9b-ecd36c9af225
add key=ENCRYPTION list=xvr value=none
add key=FINGERPRINT_FP list=xvr value=chrome
add key=SERVER_NAME_SNI list=xvr value=apple.com
add key=PUBLIC_KEY_PBK list=xvr value=fTndnleCTkK9_jtpwCAdxtEwJUkQ22oY1W8dTza2xHs
add key=SHORT_ID_SID list=xvr value=29d2d3d5a398
add key=TZ                list=xvr value=Europe/Moscow
```

7) Теперь создадим сам контейнер. Здесь вам нужно выбрать репозиторий из [Docker Hub](https://hub.docker.com/r/gritsenko/xray-mikrotik) с архитектурой под ваше устройство.



Пример импорта контейнера в ramstorage (по факту в оперативную память) для arm64. Подставьте в ```remote-image``` нужный репозиторий и отредактируйте местоположение контейнера в ```root-dir``` при необходимости.

```
/container/add remote-image=gritsenko/xray-mikrotik:arm64 hostname=xray-vless interface=xray-vless logging=no start-on-boot=yes envlist=xvr root-dir=/docker/container-xray-mikrotik
```
Подождите немного пока контейнер распакуется до конца. В итоге у вас должна получиться похожая картина, в которой есть распакованный контейнер и окружение envs. Если в процессе импорта возникают ошибки, внимательно читайте лог из RouterOS.

![img](Demonstration/1.1.png)

![img](Demonstration/1.2.png)

:anger:
Контейнер будет использовать только локальный DNS сервер на IP адресе 172.18.20.5. Необходимо разрешить DNS запросы TCP/UDP порт 53 на данный IP в правилах RouterOS в разделе ```/ip firewall filter```

8) Запускаем контейнер через WinBox в разделе меню Winbox "container". В логах MikroTik вы увидите характерные сообщения о запуске контейнера. 

:fire::fire::fire: Поздравляю! Настройка завершена. Можно проверить доступность IP 8.8.8.8 из списка "to_vpn" (этот адрес мы добавили ранее).
 
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

| Переменная | Пример значения (у вас должны быть свои) | Пояснение | 
|:----------:|:----------:|:----------:|
| SERVER_ADDRESS    | myhost.com   | Конфигурация Xray клиента  |
| SERVER_PORT    | 443   | Конфигурация Xray клиента  |
| USER_ID    | e3203dfe-9s62-4de5-bf9b-ecd36c9af225   | Конфигурация Xray клиента  |
| ENCRYPTION    | none   | Конфигурация Xray клиента  |
| FINGERPRINT_FP    | chrome   | Конфигурация Xray клиента  |
| SERVER_NAME_SNI    | apple.com   | Конфигурация Xray клиента  |
| PUBLIC_KEY_PBK    | fTndnleCTkK9_jtpwCAdxtEwJUkQ22oY1W8dTza2xHs   | Конфигурация Xray клиента  |
| SHORT_ID_SID    | 29d2d3d5a398   | Конфигурация Xray клиента  |
| GATEWAY    | 172.18.20.5   | IP шлюз по-умолчанию в Linux (подсмотреть через ```ip r```)|
| ADAPTER_NAME    | eth0   | Название физического адаптера в Linux (подсмотреть через ```ip a```) |

```
#!/bin/sh
echo "Starting setup Linux please wait"
pkill xray
pkill tun2socks
sleep 1

# Заполните данные переменные из
SERVER_ADDRESS=***
SERVER_PORT=***
USER_ID=***
ENCRYPTION=***
FINGERPRINT_FP=***
SERVER_NAME_SNI=***
PUBLIC_KEY_PBK=***
SHORT_ID_SID=***
GATEWAY=***
ADAPTER_NAME=***


# Получение IP-адреса
SERVER_IP_ADDRESS=$(getent ahosts $SERVER_ADDRESS | head -n 1 | awk '{print $1}')

if [ -z "$SERVER_IP_ADDRESS" ]; then
  echo "Failed to obtain an IP address for FQDN $SERVER_ADDRESS"
  exit 1
fi

# Сетевые настройки
ip tuntap del mode tun dev tun0
ip tuntap add mode tun dev tun0
ip addr add 172.31.200.10/30 dev tun0
ip link set dev tun0 up
ip route del default via $GATEWAY
ip route add default via 172.31.200.10
ip route add $SERVER_IP_ADDRESS/32 via $GATEWAY
ip route add 1.0.0.1/32 via $GATEWAY
ip route add 8.8.4.4/32 via $GATEWAY
ip route add 192.168.0.0/16 via $GATEWAY
ip route add 10.0.0.0/8 via $GATEWAY
ip route add 172.16.0.0/12 via $GATEWAY


# Обновление resolv.conf
rm -f /etc/resolv.conf
tee -a /etc/resolv.conf <<< "nameserver $GATEWAY"
tee -a /etc/resolv.conf <<< "nameserver 1.0.0.1"
tee -a /etc/resolv.conf <<< "nameserver 8.8.4.4"

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
        "auth": "noauth",
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
      "settings": {
        "vnext": [
          {
            "address": "$SERVER_ADDRESS",
            "port": $SERVER_PORT,
            "users": [
              {
                "id": "$USER_ID",
                "encryption": "$ENCRYPTION",
                "alterId": 0
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "fingerprint": "$FINGERPRINT_FP",
          "serverName": "$SERVER_NAME_SNI",
          "publicKey": "$PUBLIC_KEY_PBK",
          "spiderX": "",
          "shortId": "$SHORT_ID_SID"
        }
      },
	  "tag": "proxy"
    }
  ]
}
EOF
echo "Start Xray core"
/opt/xray/xray run -config /opt/xray/config/config.json &
echo "Start tun2socks"
/opt/tun2socks/tun2socks -loglevel silent -tcp-sndbuf 3m -tcp-rcvbuf 3m -device tun0 -proxy socks5://127.0.0.1:10800 -interface $ADAPTER_NAME &
echo "Linux customization is complete"
```

Сохраняем и делаем файл исполняемым

```
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
:fire::fire::fire: Поздравляю! Настройка завершена. Можно проверить доступность IP 8.8.8.8 из списка "to_vpn" (этот адрес мы добавили ранее). Трафик должен уходить на Debian.
IP адреса назначения, которые MikroTik завернёт в Xray, будут отправляться на Debian, а он в свою очередь завернёт трафик на виртуальный tun0 адаптер, который адресует весь трафик в socks proxy Xray.

[Donate :sparkling_heart:](https://telegra.ph/Youre-making-the-world-a-better-place-01-14)


