# OPNsense Bootstrap Rehberi

Bu rehber, OPNsense sanal makinesinin (Live CD modundan çıkarılıp) kalıcı olarak Proxmox diskine kurulmasını, başlangıç ağ ayarlarının yapılmasını ve Ansible üzerinden otomatik konfigürasyon (provisioning) sürecine hazır hale getirilmesini adım adım açıklar.

## 1. OPNsense'in Kalıcı Olarak Diske Kurulması (Installer)

Terraform ilk çalıştığında OPNsense'i Live CD (ISO) üzerinden başlatır. Bu aşamada yapılan hiçbir ayar kalıcı değildir.

1. Proxmox web arayüzüne (`https://192.168.1.200:8006`) girin ve OPNsense sanal makinesinin (VM 100) konsol (Console) ekranını açın.
2. Ekranda **OPNsense ana menüsü** (0-13 arası seçenekler) açıksa, **`0` (Logout)** tuşlayıp çıkış yapın.
3. Karşınıza Login (giriş) ekranı gelecektir.
   * **Kullanıcı adı:** `installer`
   * **Şifre:** `opnsense`
4. Giriş yaptığınızda mavi ekranlı OPNsense Kurulum Sihirbazı başlayacaktır.
5. Yön tuşlarıyla ilerleyerek standart kurulumu (örneğin UFS veya ZFS ile) disk üzerine gerçekleştirin. (Varsayılan ayarlar home lab için genellikle uygundur).
6. Kurulum tamamlandıktan sonra menüden **Reboot** seçeneğiyle makineyi yeniden başlatın. (Terraform sanal makineyi oluştururken boot önceliğini diske verdiği için CD'den değil, yeni kurulan sistemden açılacaktır).

## 2. İlk Kurulum Sonrası Ağ (IP) Ayarlarının Yapılması

Sistem yeniden başladıktan sonra kalıcı diskten açılacak ve tekrar konsol ana menüsü karşınıza gelecektir.

1. Ana menüden **`2` (Set interface IP address)** seçeneğini tuşlayın.
2. Arayüzler listelenecektir. WAN (Dış Ağ) arayüzünü (genellikle `1` numaradır, `vtnet0`) seçin.
3. Sorulacak sorulara sırasıyla şu yanıtları verin:
   * *Configure IPv4 address WAN interface via DHCP?* -> **`n`**
   * *Enter the new WAN IPv4 address* -> **`192.168.1.201`**
   * *Enter the new WAN IPv4 subnet bit count* -> **`24`**
   * *For a WAN, enter the new IPv4 upstream gateway address* -> **`192.168.1.1`** *(Ev modeminizin IP'si)*
   * *Do you want to use the gateway as the IPv4 name server, too?* -> **`y`** (veya sadece Enter)
   * *Configure IPv6 address WAN interface via DHCP6?* -> **`n`**
   * *Do you want to revert to HTTP as the web GUI protocol?* -> **`n`**
4. (İsteğe Bağlı Kontrol): Aynı işlemi menüden LAN (İç Ağ) bacağı (`vtnet1`) için de teyit edebilirsiniz. LAN IP'si `10.10.10.1`, subnet'i `24` olmalı ve LAN'ın **Ağ Geçidi (Upstream Gateway) kısmı kesinlikle boş bırakılmalıdır (None/Auto)**.

## 3. Web Arayüzüne Erişim İçin Firewall'un Geçici Olarak Kapatılması

OPNsense, güvenlik gereği WAN üzerinden gelen tüm istekleri (arayüz erişimi dahil) varsayılan olarak engeller. İçeri girebilmek için:

1. OPNsense ana menüsünden **`8` (Shell)** seçeneğine girin.
2. Konsola şu komutu yazıp Enter'a basın:
   ```bash
   pfctl -d
   ```
3. Ekranda `pf disabled` yazısını görmelisiniz. Bu işlem OPNsense güvenlik duvarını siz cihazı yeniden başlatana kadar devre dışı bırakır.

## 4. API Anahtarı (API Key) Oluşturulması

Ansible'ın (projenizdeki otomasyonun) OPNsense cihazına bağlanıp ayarları yapabilmesi için bir API anahtarına ihtiyacı vardır.

1. Bilgisayarınızın tarayıcısından **`https://192.168.1.201/`** adresine gidin.
2. Giriş ekranında **`root`** ve kurulum aşamasında belirlediğiniz şifreyi (değiştirmediyseniz `opnsense`) kullanarak giriş yapın.
3. Sol taraftaki menüden **System -> Access -> Users** yolunu izleyin.
4. Listeden `root` kullanıcısının sağındaki kalem (Edit) ikonuna tıklayın.
5. Açılan sayfanın en altına doğru inin, **API keys** başlığını bulun.
6. Altındaki artı **(+)** butonuna basın.
7. Bilgisayarınıza otomatik olarak bir metin dosyası indirilecektir. Dosyanın içinde `key` (anahtar) ve `secret` (gizli anahtar) olmak üzere iki adet değer bulunmaktadır.

## 5. Projedeki .env Dosyasının Güncellenmesi

İndirdiğiniz dosyadaki bilgileri, Ansible'ın okuyabileceği proje ortam değişkenlerinize (environment variables) eklemeniz gerekir.

1. `ProxmoxHomeLab` projenizin ana dizinindeki **`.env`** dosyasını açın (yoksa oluşturun veya `.env.example` dosyasını kopyalayın).
2. Dosyanın içine az önce ürettiğiniz bilgileri şu formata uygun şekilde ekleyin:

```ini
proxmox_passwd=PROXMOX_SIFRENIZI_BURAYA_YAZIN
opnsense_api_key=BURAYA_INDIRILEN_KEY_YAZILACAK
opnsense_api_secret=BURAYA_INDIRILEN_SECRET_YAZILACAK
```

## 6. Otomasyonun (Ansible) Çalıştırılması

Tüm hazırlıklar tamam! Artık repodaki ağ ve güvenlik duvarı konfigürasyonlarını (DHCP havuzları, kurallar, alias'lar, vb.) OPNsense'e Ansible ile yükleyebiliriz.

1. Projenin ana dizininde bir WSL / Linux terminali açın.
2. Aşağıdaki komutları sırasıyla çalıştırın:

```bash
cd ansible
ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i inventories/production/hosts.yml playbooks/opnsense/site.yml
```

> **Not:** Windows üzerinden WSL (*Örn:* `/mnt/c/Users/...`) çalıştırıyorsanız, dosya yetki hatalarını atlamak adına komutun başındaki `ANSIBLE_CONFIG=ansible.cfg` kısmı zorunludur.

Tebrikler! Ansible komutu hatasız çalıştığında `locals.tf` dosyanızda belirlediğiniz tüm ağ altyapısı, sanal makine IP tahsisleri ve güvenlik duvarı kuralları (WAN tarafı anti-lockout kuralı da dahil) cihazınıza başarıyla uygulanmış olacaktır. Artık OPNsense cihazınızı güvenle yeniden başlatabilir veya `pfctl -e` komutuyla firewall korumasını geri açabilirsiniz.

---

## Ekstra: Sorun Giderme (Troubleshooting)

### OPNsense Ağdan Kopuyor / Pinglere "No route to host" Veriyorsa

OPNsense'i yeniden başlattıktan sonra cihaz IP almasına rağmen ağ ile (veya Proxmox sunucusuyla) iletişim kuramıyorsa, Proxmox sanal makinenin "ağ kablosunu" yazılımsal olarak çekmiş (`link_down=1`) olabilir. Bu durumu düzeltmek (kabloyu tekrar takmak) için Proxmox sunucunuzun terminaline veya SSH bağlantısına giderek şu komutu çalıştırın:

```bash
# VM ID'niz 100 ve WAN bacağınız net0 ise:
qm set 100 -net0 virtio=02:7A:AA:5D:AD:51,bridge=vmbr0,firewall=0,link_down=0
```

> **Not:** `02:7A:AA:5D:AD:51` yerine kendi VM'nizin donanım (MAC) adresini kullanmalısınız. MAC adresinizi `qm config 100` yazarak `net0` satırında görebilirsiniz. Komut sonundaki `link_down=0` ifadesi kablonun fiziksel olarak "takılı" duruma getirilmesini sağlar.
