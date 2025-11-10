# VPS Ubuntu Web Apps

Este repositorio incluye aplicaciones web escritas en diferentes lenguajes de programación, junto con los scripts necesarios para desplegarlas en un servidor VPS con Ubuntu.


## `production_setup.sh`

Antes de configurar las aplicaciones, es necesario preparar el servidor.

### Pasos

1. Conéctate al servidor por SSH:

```sh
ssh root@<server-ip>
```

2. Clona el repositorio:

```sh
git clone https://github.com/ichigar/imw-vps-gowebapp.git
```

3. Asigna permisos de ejecución y ejecuta el script:

```sh
chmod +x production_setup.sh
./production_setup.sh
```

### Instrucciones posteriores a la instalación

1. Las llaves SSH se han configurado para el usuario `user` usando las llaves autorizadas del usuario `root`. Verifica que puedes acceder al servidor como `user`:

```sh
ssh user@<server-ip>
```

2. El usuario `root` aún puede iniciar sesión mediante autenticación por llave pública (útil para mantenimiento), pero se recomienda usar el usuario `user` para las operaciones diarias.

3. Si encuentras errores al conectarte al servidor:

   * Revisa la configuración de SSH:

     ```sh
     cat /etc/ssh/sshd_config
     ```

   * Verifica las reglas del firewall:

     ```sh
     sudo ufw status
     ```

   * Comprueba el estado del servicio SSH:

     ```sh
     sudo systemctl status ssh
     ```

4. Recuerda que la autenticación por contraseña está deshabilitada por razones de seguridad.
   Solo podrás iniciar sesión mediante llaves SSH.


## Go Web App

### Pasos para desplegar la aplicación

1. Inicia sesión como el usuario `user`:

```sh
ssh user@<server-ip>
```

2. Clona el repositorio:

```sh
git clone https://github.com/ichigar/imw-vps-gowebapp.git
```

3. Accede al directorio de la aplicación escrita en Go:

```sh
cd vps_ubuntu_web_apps/gowebapp
```

4. Ejecuta el script de configuración:

```sh
sudo bash production_setup.sh
```

5. Accede a la aplicación desde tu navegador en:
   `http://<server-ip>:8080`

## Proxy inverso con caddy

El repositorio incluye un script de configuración de proxy inverso que permite accediendo por https a un dominio con un registro A que apunta a la VPS redireccionar la petición a una app que esté a la escucha en `127.0.0.1` en el puerto especificado al ejecutar el script.

### Pasos para configurar el proxy inverso

Ejecutar el script de configuración de caddy pasando como parámetro el nombre del dominio, el puerto en el que la app está a la escucha y el email de contacto para el certificado:

```sh
sudo bash setup_caddy_reverse_proxy example.com 8080 admin@example.com
```

Al acceder desde el navegador a <https://example.com> se debería abrir la aplicación que está a la escucha en <http://127.0.0.1:8080> en el servidor

Si queremos añadir otra aplicación local para ser accesible con el proxy inverso no tenemos más que crear un registro A en el servidor de DNS que apunte a la ip del servidor y editar el fichero `/etc/caddy/Caddyfile` para añadir los datos de acceso a la nueva app.

```sh
# Caddyfile generado automáticamente
{
        email admin@example.com
        # logging global opcional:
        # log {
        #   output file /var/log/caddy/access.log
        #   level INFO
        # }
}

example.com {
        encode zstd gzip
        header {
                # Seguridad básica
                Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
                X-Content-Type-Options "nosniff"
                X-Frame-Options "DENY"
                Referrer-Policy "strict-origin-when-cross-origin"
        }
        reverse_proxy 127.0.0.1:8080
        # Si usas websockets o SSE, Caddy lo maneja automáticamente en reverse_proxy.
}

# Añadido manualmente para acceder a la nueva app asociada al dominio de ejemplo newapp.com
newapp.com {
        encode zstd gzip
        header {
                # Seguridad básica
                Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
                X-Content-Type-Options "nosniff"
                X-Frame-Options "DENY"
                Referrer-Policy "strict-origin-when-cross-origin"
        }
        reverse_proxy 127.0.0.1:8081
        # Si usas websockets o SSE, Caddy lo maneja automáticamente en reverse_proxy.
}
```