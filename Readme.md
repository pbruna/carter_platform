# Carter Platform
Repositorio con la configuración de Puppet para la automatización de la plataforma de Carter.

## Configuracion Sistema Operativo

### Instalación dependencias

1. Se debe configurar el repositorio EPEL
2. Se deben instalar los paquetes puppet y git, y el grupo desarrollo de software
3. Se debe instalar nodejs desde http://vibol.hou.cc/files/x86_64/nodejs-0.6.15-1.x86_64.rpm
4. Desactivar SELinux


### Configuración con Puppet

1. Descargar configuración de Puppet
```bash
git clone git://github.com/pbruna/carter_platform.git
```

2. Copiar directorio contenido de directorio carter_platform/puppet a /etc/puppet

3. Ejecutar puppet de forma local
```bash
puppet apply /etc/puppet/manifests/default
```

4. Esperar

5. Copiar archivo carter_platform/logstasth_plugin/carter.rb a /opt/logstash/plugins/logstash/outputs/

6. Reiniciar