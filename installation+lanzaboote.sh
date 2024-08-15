#!/usr/bin/env bash

deviceHandler() {
  if [[ ! $1 =~ ^(sd[a-zA-Z0-9]*|nvme[a-zA-Z0-9]*|mmcblk[a-zA-Z0-9]*|md[a-zA-Z0-9]*) ]]; then
     printf "Err. incorrect input. \nInput must start with /dev/storagedevice.\n"
    return 1
  fi
}

declare -g swapsize
swapSizeHandler() {
  echo "Creating swap partition..."
  while true; do
    printf "\nPlease enter swap size.\nEnter an empty value for default: 8GiB\n"
    read -p "Enter: " swapsize 
    if [[ $swapsize =~ ^[0-9]+(MiB|GiB)$ ]]; then
      echo "Entering: $1"
      $1
      break
    elif [[ -z $swapsize ]]; then
      echo "Entering default values for swap..."
      $2
      break
    else
      echo "Err. Invalid Input."
    fi
  done
}

ext4Swap() {
  parted /dev/"$device" -- mkpart primary linux-swap "-$swapsize"
}

ext4DefaultSwap() {
  parted /dev/"$device" -- mkpart primary linux-swap -8GiB 100%
}

btrfsSwap() {
  lvcreate --size "$swapsize" --name swap lvm
}

btrfsDefaultSwap() {
  lvcreate --size 8GiB --name swap lvm
}

btrfsSubVolHandler() { 
  subvolloc_array=() 
  subvolname_array=() 
 
  echo "How many subvolumes to create?" 
  read -p "Enter: " subvolnum 
  while true; do 
    if [[ $subvolnum -le 0 || ! $subvolnum =~ ^[0-9]+$ ]]; then 
      echo "Err. Not a number." 
      read -p "Enter: " subvolnum 
    else 
      break 
    fi 
  done 
 
  mount -t "$fsys" /dev/disk/by-label/nixos /mnt
  for((i=1; i<=$subvolnum; i++)); do 
    printf "\nEnter [root] as name if mounting [/mnt || /].\nEnter the name of subvolume #$i\n" 
    read -p "Enter: " subvolname 
 
    while true; do 
      if [[ -z $subvolname ]]; then 
        printf "Err. Empty value provided\nPlease input a value\n" 
        read -p "Enter: " subvolname 
      else 
        break 
      fi 
    done 
    subvolname_array+=("$subvolname") 
 
    if [[ ! $subvolname == "root" ]]; then 
      printf "\nEnter subvolume location\n" 
      read -p "/mnt/" subvolloc 
      subvolloc_array+=("/mnt/$subvolloc") 
    else 
      subvolloc_array+=("/mnt") 
    fi 
 
    echo "Creating btrfs subvolume for $subvolname at /mnt/$subvolname..." 
    btrfs subvolume create /mnt/"$subvolname"
 
  done 
  echo "Creating snapshots..." 
  btrfs subvolume snapshot -r /mnt/root /mnt/root-blank
 
  printf "\nPreparing to mount subvolumes...\nUnmounting /mnt...\n" 
  umount /mnt
 
  for ((i=0; i<$subvolnum; i++)); do 
    subvolloc="${subvolloc_array[$i]}" 
    subvolname="${subvolname_array[$i]}" 
 
    mkdir -p "$subvolloc"
    mount -o subvol="$subvolname",compress=zstd,noatime /dev/disk/by-label/nixos "$subvolloc"
  done 
 
} 
 
main() {
  printf "Installation for NixOS by Hans. \nYou are responsible for any data loss.\n"
  read -p "[Y/N]: " agree
  if [[ ! $agree = "Y" || $agree = "y" ]]; then
    echo "Exiting..."
    exit 1
  fi

  echo "Checking root permissions..."
  if [[ $EUID -eq 0 ]]; then
  	printf "$USER is root.\nProceeding..\n"
  else
  	printf "$USER is not root.\nPlease try again as root user\n"
	  exit 1
  fi

  echo "Checking secureboot keys in current directory..."
  if [[ -d "./secureboot" ]]; then
    printf "./secureboot folder exist!\nProceeding...\n"
    mkdir -p /mnt/etc/
    sudo cp -r ./secureboot /mnt/etc/
    sudo chown -R root:root /mnt/etc/secureboot/
    sudo chmod -R 755 /mnt/etc/secureboot
    printf "Keys have been moved to /mnt/etc/secureboot\n"
  else
    printf './secureboot does not exist! \nMake sure you have lanzaboote installed and have the generated "sudo sbctl create-keys" in the current folder! \nExiting..\n'
    exit 1
  fi

  lsblk
  printf "The following commands will wipe the storage device.\nPlease type your storage drive NOT the partition. e.g /dev/sda, etc.\n"
  read -p "/dev/" device
  while true; do
    deviceHandler $device
    if [[ $? == 1 ]]; then
      read -p "/dev/" device
    else
      break
    fi
  done
  echo "Choose the partitioning scheme"
  echo "Please enter GPT or MBR."
  read -p "[GPT/MBR]: " partscheme
  while true; do
    case $partscheme in
      GPT | gpt) 
    	printf "\nWiping device...\nConverting to GPT..."
        parted /dev/"$device" -- mklabel gpt
        break 
        ;;
      MBR | mbr)
    	printf "\nWiping device...\nConverting to MBR..."
        parted /dev/"$device" -- mklabel msdos
        break 
        ;;
      *)
        echo "Invalid Partition Scheme: $partscheme."
        echo "Please enter GPT or MBR."
        read -p "[GPT/MBR]: " partscheme
        ;;
    esac
  done

  printf "\nPlease type your options for the primary partition.\ne.g. 1GiB 100%% | Meaning 1GiB will be left out and 100%% will be occupied.\nYou could also do something like: 1GiB -8GiB | Meaning it will leave 1GiB of space for boot options later and occupy all-space-left minus 8GiB.\nThis is particularly useful since you can use -8GiB as swapsize later and use the 1GiB for the boot options.\nEnter an empty value for default: 1GiB -8GiB\n"
  read -p "Enter: " devopt
  if [[ -z $devopt ]]; then
	  printf "\nEntering default values...\nCreating primary partition...\n"
	  parted /dev/"$device" -- mkpart primary 1GiB -8GiB
  else
	  echo "Entering: parted /dev/$device -- mkpart primary $devopt."
          echo "Creating primary partition..."
	  parted /dev/"$device" -- mkpart primary $devopt
  fi
  
  printf "\nPlease type your boot options.\nEnter an empty value for default: 1MiB 1GiB\n"
  read -p "Enter: " devbootopt
  if [[ -z $devbootopt ]]; then
	  printf "\nEntering default values...\nCreating ESP partition.\n"
	  parted /dev/"$device" -- mkpart ESP fat32 1MiB 1GiB
  else
	  echo "Entering: parted /dev/$device -- mkpart ESP fat32 $devbootopt."
          echo "Creating ESP partition."
	  parted /dev/"$device" -- mkpart ESP fat32 "$devbootopt"
  fi
  parted /dev/$device -- set 2 esp on

  lsblk
  printf "\nPlease type the primary partition.\ne.g. /dev/sda1 | Meaning the first partition of sda\n"
  read -p "/dev/" devrootpart
  while true; do
    deviceHandler $devrootpart
    if [[ $? == 1 ]]; then
      read -p "/dev/" devrootpart
    else
      break
    fi
  done
  printf "\nPlease choose the filesystem.\next4 | btrfs\n"
  read -p "[ext4/btrfs]: " fsys
  while true; do
    if [[ $fsys == "ext4" ]]; then
      swapSizeHandler ext4Swap ext4DefaultSwap
      mkfs.ext4 -L nixos /dev/sda1
      mkswap -L swap /dev/sda3
			swapon /dev/sda3
      mount /dev/disk/by-label/nixos /mnt
      break
    elif [[ $fsys == "btrfs" ]]; then
      cryptsetup --verify-passphrase -v luksFormat /dev/"$devrootpart"
      cryptsetup open /dev/"$devrootpart" enc
      echo "Creating swap inside encrypted partition..."
      pvcreate /dev/mapper/enc
      vgcreate lvm /dev/mapper/enc
      swapSizeHandler btrfsSwap btrfsDefaultSwap
      lvcreate --extents 100%FREE --name root lvm
      mkswap -L swap /dev/lvm/swap
      swapon /dev/lvm/swap
      mkfs.btrfs -L nixos /dev/lvm/root
      break
    else
      printf "\nErr. Invalid Input.\nPlease choose between: ext4 | btrfs.\n"
      read -p "Enter: " fsys
    fi
  done

  lsblk
  echo "Please enter the boot partition device"
  read -p "/dev/" devbootpart
  while true; do
    deviceHandler $devbootpart
    if [[ $? == 1 ]]; then
      read -p "/dev/" devbootpart
    else
      mkfs.vfat -n boot /dev/"$devbootpart"
      break
    fi
  done

  if [[ $fsys == "btrfs" ]]; then
    btrfsSubVolHandler
  else
    echo "$fsys is not of btrfs."
    echo "Skipping..."
  fi

  echo "Mounting boot partition..."
  mkdir /mnt/boot
  mount /dev/disk/by-label/boot /mnt/boot

  echo "SUCCESS"
  return 0
}

main
