#!/bin/bash

##############################################################################################################################
# Author: Moutaz Muhammad <moutazmuhamad@gmail.com>
# Support Ubuntu 16, 20, 22, 24, CentOS, and Red Hat

# Setup odoo11 & odoo14 environment
# curl -s https://raw.githubusercontent.com/moutazmuhammad/odoo-docker-compose/main/Dockerfile/scripts/linux_setup.sh | bash
##############################################################################################################################
set -e

# Base directory for the project
BASE_DIR="${BASE_DIR:-$PWD/ODOO_WORK}"
mkdir -p $BASE_DIR
VERSIONS=("11" "14")

# Detect OS and version
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    echo "Cannot determine OS"
    exit 1
fi

# Function to check and install Docker
check_install_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Docker not found. Installing Docker..."
        if [ "$OS" == "ubuntu" ]; then
            sudo apt-get update
            sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
            sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io
        elif [ "$OS" == "centos" ] || [ "$OS" == "rhel" ]; then
            if [[ "$VER" == 7.* ]]; then
                sudo yum remove -y docker docker-common docker-selinux docker-engine
                sudo yum install -y yum-utils device-mapper-persistent-data lvm2
                sudo yum-config-manager --add-repo https://download.docker.com/linux/$OS/docker-ce.repo
                sudo yum install -y docker-ce
            else
                sudo dnf -y install dnf-plugins-core
                sudo dnf config-manager --add-repo https://download.docker.com/linux/$OS/docker-ce.repo
                sudo dnf install -y docker-ce docker-ce-cli containerd.io
            fi
            sudo systemctl enable docker.service
            sudo systemctl start docker.service
        else
            echo "Unsupported OS: $OS"
            exit 1
        fi

        # Allow current user to run Docker without sudo
        sudo groupadd docker 2>/dev/null || true
        sudo usermod -aG docker "$USER"
        sudo chmod 666 /var/run/docker.sock

    else
        echo "[INFO] Docker is already installed."
    fi
}

# Function to check and install Docker Compose
check_install_docker_compose() {
    if ! command -v docker-compose &> /dev/null; then
        echo "[INFO] Docker Compose not found. Installing Docker Compose..."
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        echo "[INFO] Docker Compose installed successfully."
    else
        echo "[INFO] Docker Compose is already installed."
    fi
}


# Function to create directory structure
create_directory_structure() {
    for version in "${VERSIONS[@]}"; do
        mkdir -p "$BASE_DIR/odoo${version}/addons"
        mkdir -p "$BASE_DIR/odoo${version}/config"
    done
}

# Function to create docker-compose.yaml for Odoo 14
create_docker_compose_14() {
    cat > "$BASE_DIR/odoo14/docker-compose.yaml" << 'EOF'
---
services:
  odoo14:
    container_name: odoo14
    image: moutazmuhammad/odoo:14.0
    restart: always 
    depends_on:
      - db14
    ports:
      - "1469:8069"
      - "1472:8072"
    environment:
      - DB_HOST=db14
      - DB_PORT=5432
      - DB_USER=odoo14
      - DB_PASSWORD=odoo14
    volumes:
      - odoo14-web-data:/var/lib/odoo
      - ./config:/etc/odoo
      - ./addons:/mnt/extra-addons
      
  db14:
    container_name: db14
    image: postgres:14
    restart: always 
    environment:
      - POSTGRES_DB=postgres
      - POSTGRES_PASSWORD=odoo14
      - POSTGRES_USER=odoo14
    volumes:
      - odoo14-db-data:/var/lib/postgresql/data

volumes:
  odoo14-web-data:
  odoo14-db-data:
EOF
}

# Function to create docker-compose.yaml for Odoo 11
create_docker_compose_11() {
    cat > "$BASE_DIR/odoo11/docker-compose.yaml" << 'EOF'
---
services:
  odoo11:
    container_name: odoo11
    image: moutazmuhammad/odoo:11.0
    restart: always 
    depends_on:
      - db11
    ports:
      - "1169:8069"
      - "1172:8072"
    environment:
      - DB_HOST=db11
      - DB_PORT=5432
      - DB_USER=odoo11
      - DB_PASSWORD=odoo11
    volumes:
      - odoo11-web-data:/var/lib/odoo
      - ./config:/etc/odoo
      - ./addons:/mnt/extra-addons
      
  db11:
    container_name: db11
    image: postgres:14
    restart: always 
    environment:
      - POSTGRES_DB=postgres
      - POSTGRES_PASSWORD=odoo11
      - POSTGRES_USER=odoo11
    volumes:
      - odoo11-db-data:/var/lib/postgresql/data

volumes:
  odoo11-web-data:
  odoo11-db-data:
EOF
}

# Function to create odoo.conf for Odoo 14
create_odoo_conf_14() {
    cat > "$BASE_DIR/odoo14/config/odoo.conf" << 'EOF'
[options]
admin_passwd = admin14
db_host = db14
db_port = 5432
db_user = odoo14
db_password = odoo14

addons_path = /opt/odoo/addons,/mnt/extra-addons
data_dir = /var/lib/odoo
EOF
}

# Function to create odoo.conf for Odoo 11
create_odoo_conf_11() {
    cat > "$BASE_DIR/odoo11/config/odoo.conf" << 'EOF'
[options]
admin_passwd = admin11
db_host = db11
db_port = 5432
db_user = odoo11
db_password = odoo11

addons_path = /opt/odoo/addons,/mnt/extra-addons
data_dir = /var/lib/odoo
EOF
}

# Function to start Docker containers
start_containers() {
    for version in "${VERSIONS[@]}"; do
        echo "[INFO] Starting Odoo ${version} containers..."
        cd "$BASE_DIR/odoo${version}"
        docker-compose up -d
        echo "[INFO] Odoo ${version} containers started"
    done
}

create_restart_commands() {
    echo "Creating custom restart commands..."

    # Make sure we have write permission to /usr/local/bin/
    sudo chmod u+w /usr/local/bin/

    # Create restart-odoo11 command
    echo '#!/bin/bash' | sudo tee /usr/local/bin/restart-odoo11 > /dev/null
    echo "cd $BASE_DIR/odoo11 && docker-compose restart" | sudo tee -a /usr/local/bin/restart-odoo11 > /dev/null
    # Create restart-odoo14 command
    echo '#!/bin/bash' | sudo tee /usr/local/bin/restart-odoo14 > /dev/null
    echo "cd $BASE_DIR/odoo14 && docker-compose restart" | sudo tee -a /usr/local/bin/restart-odoo14 > /dev/null
    # Create stop-odoo11 command
    echo '#!/bin/bash' | sudo tee /usr/local/bin/stop-odoo11 > /dev/null
    echo "cd $BASE_DIR/odoo11 && docker-compose down" | sudo tee -a /usr/local/bin/stop-odoo11 > /dev/null
    # Create stop-odoo14 command
    echo '#!/bin/bash' | sudo tee /usr/local/bin/stop-odoo14 > /dev/null
    echo "cd $BASE_DIR/odoo14 && docker-compose down" | sudo tee -a /usr/local/bin/stop-odoo14 > /dev/null
    # Create start-odoo11 command
    echo '#!/bin/bash' | sudo tee /usr/local/bin/start-odoo11 > /dev/null
    echo "cd $BASE_DIR/odoo11 && docker-compose up -d" | sudo tee -a /usr/local/bin/start-odoo11 > /dev/null
    # Create start-odoo14 command
    echo '#!/bin/bash' | sudo tee /usr/local/bin/start-odoo14 > /dev/null
    echo "cd $BASE_DIR/odoo14 && docker-compose up -d" | sudo tee -a /usr/local/bin/start-odoo14 > /dev/null
    
    sudo chmod +x /usr/local/bin/*-odoo*
    
}

# Main execution
echo "[INFO] Setting up Odoo development environment..."

# Check and install prerequisites
check_install_docker
check_install_docker_compose

# Create directory structure
create_directory_structure

# Create configuration files
create_docker_compose_14
create_docker_compose_11
create_odoo_conf_14
create_odoo_conf_11

# Start containers
start_containers
create_restart_commands


echo -e "\n\033[1;32m+###############################################################################################################################+\033[0m"
echo -e "\033[1;32m  ✅  Odoo development environment setup complete! Your Odoo development environment is ready for use. Here’s how to get started: \033[0m"
echo -e "\n\033[1;32m+###############################################################################################################################+\033[0m"
echo -e "\033[1;32m                                                           \033[0m"
echo -e "\033[1;34m  🔧 **Working with Odoo:**                                 \033[0m"
echo -e "\033[1;34m      ➤ You can access Odoo 14 at: \033[1;36m🔗 http://localhost:1469   \033[0m"
echo -e "\033[1;34m      ➤ You can access Odoo 11 at: \033[1;36m🔗 http://localhost:1169   \033[0m"
echo -e "\033[1;32m                                                           \033[0m"
echo -e "\033[1;34m  💡 **How to add custom modules:**                         \033[0m"
echo -e "\033[1;34m          1. Navigate to the 'addons' directory for the version of Odoo you want to work with: \033[0m"
echo -e "\033[1;34m             - Odoo 14: $BASE_DIR/odoo14/addons                    \033[0m"
echo -e "\033[1;34m             - Odoo 11: $BASE_DIR/odoo11/addons                    \033[0m"
echo -e "\033[1;34m          2. Place your custom modules inside the respective 'addons' folder. \033[0m"
echo -e "\033[1;34m          3. **Important:** If your custom modules are not detected by Odoo, you might need to add the path to your 'addons' directory in the corresponding \`odoo.conf\` file. \033[0m"
echo -e "\033[1;34m             - You can find the \`odoo.conf\` file at:               \033[0m"
echo -e "\033[1;34m               - Odoo 14: $BASE_DIR/odoo14/config/odoo.conf        \033[0m"
echo -e "\033[1;34m               - Odoo 11: $BASE_DIR/odoo11/config/odoo.conf        \033[0m"
echo -e "\033[1;34m          4. Restart Odoo to see the new modules appear by running one of the following commands: \033[0m"
echo -e "\033[1;34m             - Restart Odoo 14: \033[1;36mrestart-odoo14\033[0m                    \033[0m"
echo -e "\033[1;34m             - Restart Odoo 11: \033[1;36mrestart-odoo11\033[0m                    \033[0m"
echo -e "\033[1;32m                                                           \033[0m"
echo -e "\033[1;34m  💡 **Commands created:**                                  \033[0m"
echo -e "\033[1;34m       ➤ \033[1;36mstop-odoo11\033[0m                                            \033[0m"
echo -e "\033[1;34m       ➤ \033[1;36mstop-odoo14\033[0m                                            \033[0m"
echo -e "\033[1;34m       ➤ \033[1;36mstart-odoo11\033[0m                                           \033[0m"
echo -e "\033[1;34m       ➤ \033[1;36mstart-odoo14\033[0m                                           \033[0m"
echo -e "\033[1;34m       ➤ \033[1;36mrestart-odoo11\033[0m                                         \033[0m"
echo -e "\033[1;34m       ➤ \033[1;36mrestart-odoo14\033[0m                                         \033[0m"
echo -e "\033[1;32m                                                           \033[0m"
echo -e "\033[1;34m  🚀 **Development Tips:**                                  \033[0m"
echo -e "\033[1;34m      - Use Docker Compose to manage the environment easily.   \033[0m"
echo -e "\033[1;34m      - Your changes will take effect after restarting the respective Odoo container. \033[0m"
echo -e "\033[1;32m                                                           \033[0m"
echo -e "\033[1;32m  ✅  To view real-time logs for Odoo, run the following commands: \033[0m"
echo -e "\033[1;32m      - For Odoo 14: \033[1;36mdocker logs -f odoo14\033[0m \033[1;32m \033[0m"
echo -e "\033[1;32m      - For Odoo 11: \033[1;36mdocker logs -f odoo11\033[0m \033[1;32m \033[0m"
echo -e "\033[1;32m                                                           \033[0m"
echo -e "\033[1;32m  Best regards,                                             \033[0m"
echo -e "\033[1;32m  Moutaz Muhammad                                           \033[0m"
echo -e "\n\033[1;32m+###############################################################################################################################+\033[0m"


