#!/bin/bash

DIR="$(pwd)"

# Check if a youtube.apk is provided before continuing
if [ ! -e "$DIR/build/youtube.apk" ]; then
	echo
	echo -e "\e[1;31mError: ./build/youtube.apk not found\e[0m"
	echo	
	exit 1
fi

# Check if curl & git are installed before continuing
if ! command -v "curl" &> "/dev/null"; then
	echo	
	echo -e "\e[1;31mError: curl not found\e[0m"
	echo
	exit 1
fi

if ! command -v "git" &> "/dev/null"; then
	echo
	echo -e "\e[1;31mError: git not found\e[0m"
	echo
	exit 1
fi

# Check if java is installed and if not, download and extract openjdk 17
if ! command -v "java" &> "/dev/null" && [ -z "$JAVA_HOME" ]; then
	export JAVA_HOME="$(readlink -f "$DIR/openjdk")"
	if [ ! -e "$JAVA_HOME/bin/java" ]; then
		echo
		if [ ! -e "openjdk.tar.gz" ]; then
			echo "Downloading openjdk..."
			wget -q "https://download.java.net/java/GA/jdk17.0.2/dfd4a8d0985749f896bed50d7138ee7f/8/GPL/openjdk-17.0.2_linux-x64_bin.tar.gz" -O "openjdk.tar.gz"
		fi
		echo "Extracting openjdk..."
		tar xzf "openjdk.tar.gz"
		mv jdk-* "openjdk"
	fi
fi

# Set the correct java executable
if [ -z "$JAVA_HOME" ]; then
	JAVA="java"
else
	JAVA="$JAVA_HOME/bin/java"
fi

# Check the java version
if $JAVA -version 2>&1 | grep "1.8" &> "/dev/null"; then
	echo
	echo -e "\e[1;31mError: Java 8 is not supported\e[0m"
	echo
	exit 1
fi

# Check if android sdk is installed and if not, download and extract android sdk
if [ -z "$ANDROID_HOME" ] && [ -z "$ANDROID_SDK_ROOT" ]; then
	export ANDROID_HOME="$(readlink -f "$DIR/android-sdk")"
	if [ ! -e "$ANDROID_HOME" ]; then
		echo
		if [ ! -e "android-sdk.tar.gz" ]; then
			echo "Downloading Android SDK"
			curl "https://github.com/CnC-Robert/revanced-cli-script/releases/download/androidsdk/android-sdk.tar.gz" -L -s -o "android-sdk.tar.gz"
		fi
		echo "Extracting android-sdk.tar.gz"
		tar xzf "android-sdk.tar.gz"
	fi
fi

# Check if adb device is connected before continuing
if [ -n "$1" ]; then

	# Check if adb is installed before continuing
	if ! command -v "adb" &> "/dev/null"; then
		echo
		echo -e "\e[1;31mError: adb not found\e[0m"
		echo
		exit 1
	fi

	# Check if the adb device is connected
	if ! adb devices | grep "$1" &> "/dev/null"; then
		echo
		echo -e "\e[1;31mError: device $1 not connected\e[0m"
		echo
		exit 1
	fi

	# Check if adb has shell & root access
	if ! adb shell su -c exit; then
		echo
		echo -e "\e[1;31mError: device $1 either has no shell access or root access\e[0m"
		echo
		exit 1
	fi

else
	echo
	echo -e "\e[1;33mWarning: no adb device specified. It is recommended to do so to automatically install the patched apk\e[0m"
fi

echo
echo "Building packages..."
echo

# Clone the patcher and publish it
if [ ! -d "revanced-patcher" ]; then git clone https://github.com/revanced/revanced-patcher; fi
cd "revanced-patcher"
git pull
#git checkout v3.3.1
chmod +x "./gradlew"

if ! "./gradlew" publishToMavenLocal; then exit 1; fi

cd "$DIR"

echo

# Clone the patches and build it
if [ ! -d "revanced-patches" ]; then git clone https://github.com/revanced/revanced-patches; fi
cd "revanced-patches"
git pull
#git checkout fix-swipe-default
chmod +x "./gradlew"

if ! "./gradlew" build; then exit 1; fi

cd "$DIR"

echo

# Clone the cli and build it
if [ ! -d "revanced-cli" ]; then git clone https://github.com/revanced/revanced-cli; fi
cd "revanced-cli"
git pull
chmod +x "./gradlew"

if ! "./gradlew" build; then exit 1; fi

cd "$DIR"

echo

# Clone the integrations and build it
if [ ! -d "revanced-integrations" ]; then git clone https://github.com/LoV432/revanced-integrations; fi
cd "revanced-integrations"
git pull
#git checkout v0.30.4
git checkout reverse-swipe
chmod +x "./gradlew"

if ! "./gradlew" build; then exit 1; fi

cd "$DIR"

# Copy the cli, integrations, patches and patcher to the build directory
cp revanced-cli/build/libs/revanced-cli-*-all.jar "$DIR/build/revanced-cli.jar"
cp "$DIR/revanced-integrations/app/build/outputs/apk/release/app-release-unsigned.apk" "$DIR/build/integrations.apk"

# The cli doesn't need the files that end -sources.jar or -javadoc.jar so don't copy those 
cp "$DIR/revanced-patches/build/libs/$(ls "$DIR/revanced-patches/build/libs/" | grep -Pv "javadoc|sources")" "$DIR/build/revanced-patches.jar"
cp "$DIR/revanced-patcher/build/libs/$(ls "$DIR/revanced-patcher/build/libs/" | grep -Pv "javadoc|sources")" "$DIR/build/revanced-patcher.jar"

echo
echo "Executing the cli..."
echo

cd "$DIR/build"

# Get all patches
for PATCH in $(java -jar revanced-cli.jar -a youtube.apk -o revanced.apk -b revanced-patches.jar -l); do
	if [ "$PATCH" != "[available]" ]; then
		PATCHES="$PATCHES -i $PATCH"		
	fi 
done
PATCHES="${PATCHES:1}"

# Execute the cli and if an adb device name is given deploy on device
"$JAVA" -jar "revanced-cli.jar" -b "revanced-patches.jar" -a "youtube.apk" $(if [ -n "$1" ]; then echo "-d $1"; fi) -m "integrations.apk" -o "revanced.apk" -p "revanced-patches.jar" -t "temp"

cp "$DIR/build/revanced.apk" "$DIR/revanced.apk"

exit 0
