#!/bin/bash
/
YAML_FILE=src/ui/flutter_app/pubspec.yaml
SNAP_YAML_FILE=snap/snapcraft.yaml
SNAP_DESKTOP_FILE=snap/gui/mill.desktop
DEBIAN_YAML_FILE=src/ui/flutter_app/debian/debian.yaml
DEBIAN_DESKTOP_FILE=src/ui/flutter_app/debian/gui/mill.desktop
QT_RC_FILE=src/ui/qt/mill-pro.rc

CHANGELOG_DIRS=(
  "fastlane/metadata/android/ar/changelogs"
  "fastlane/metadata/android/bg/changelogs"
  "fastlane/metadata/android/bo/changelogs"
  "fastlane/metadata/android/cs-CZ/changelogs"
  "fastlane/metadata/android/de-DE/changelogs"
  "fastlane/metadata/android/en-US/changelogs"
  "fastlane/metadata/android/es-ES/changelogs"
  "fastlane/metadata/android/fa-IR/changelogs"
  "fastlane/metadata/android/fr/changelogs"
  "fastlane/metadata/android/gu/changelogs"
  "fastlane/metadata/android/he/changelogs"
  "fastlane/metadata/android/hi-IN/changelogs"
  "fastlane/metadata/android/hr/changelogs"
  "fastlane/metadata/android/hu-HU/changelogs"
  "fastlane/metadata/android/is-IS/changelogs"
  "fastlane/metadata/android/it-IT/changelogs"
  "fastlane/metadata/android/ja-JP/changelogs"
  "fastlane/metadata/android/ko/changelogs"
  "fastlane/metadata/android/pl-PL/changelogs"
  "fastlane/metadata/android/ru/changelogs"
  "fastlane/metadata/android/sq/changelogs"
  "fastlane/metadata/android/sr/changelogs"
  "fastlane/metadata/android/sv/changelogs"
  "fastlane/metadata/android/tr-TR/changelogs"
  "fastlane/metadata/android/uk/changelogs"
  "fastlane/metadata/android/zh-CN/changelogs"
  "fastlane/metadata/android/zh-TW/changelogs"
)

SED=sed
EDITOR=notepad

if [ "$(uname)" == "Darwin" ]; then
	SED=gsed
	EDITOR=vi
fi

if [ "$(uname)" == "Linux" ]; then
	SED=sed
	EDITOR=vi
fi

# Format source code
./format.sh

# Update Build Number
./version.sh

# version: 1.0.6+1811
VERSION_STRING=`$SED -n '4p' $YAML_FILE`
echo "VERSION_STRING = $VERSION_STRING"

# 1.0.6+1811
FULL_VERSION=`echo $VERSION_STRING | cut -d ' ' -f 2`
echo "FULL_VERSION = $FULL_VERSION"

# 1.0.6
VERSION=`echo $FULL_VERSION | cut -d "+" -f 1`
echo "VERSION = $VERSION"
OLD_VERSION=$VERSION
echo "OLD_VERSION = $OLD_VERSION"

# 6
MAJOR_NUMBER=`echo $VERSION | cut -d "." -f 1`
MINOR_NUMBER=`echo $VERSION | cut -d "." -f 2`
PATCH_NUMBER=`echo $VERSION | cut -d "." -f 3`

echo "Old:"
echo "MAJOR_NUMBER = $MAJOR_NUMBER"
echo "MINOR_NUMBER = $MINOR_NUMBER"
echo "PATCH_NUMBER = $PATCH_NUMBER"

OLD_PATCH_NUMBER=$PATCH_NUMBER
echo "OLD_PATCH_NUMBER = $OLD_PATCH_NUMBER"

# 7
arg=${1#-}
arg=${arg#-}

if [ "$arg" == "x" ]; then
  let "MAJOR_NUMBER+=1"
  MINOR_NUMBER=0
  PATCH_NUMBER=0
elif [ "$arg" == "y" ]; then
  let "MINOR_NUMBER+=1"
  PATCH_NUMBER=0
else
  let "PATCH_NUMBER+=1"
fi

echo "New:"
echo "MAJOR_NUMBER = $MAJOR_NUMBER"
echo "MINOR_NUMBER = $MINOR_NUMBER"
echo "PATCH_NUMBER = $PATCH_NUMBER"

# 1.0.7
NEW_VERSION="${MAJOR_NUMBER}.${MINOR_NUMBER}.${PATCH_NUMBER}"
echo "NEW_VERSION = $NEW_VERSION"

# 1811
BUILD_NUMBER=`echo $FULL_VERSION | cut -d "+" -f 2`
echo "BUILD_NUMBER = $BUILD_NUMBER"

# 1.0.7+1811
NEW_FULL_VERSION="$NEW_VERSION+$BUILD_NUMBER"
echo "NEW_FULL_VERSION = $NEW_FULL_VERSION"

# version: 1.0.7+1811
NEW_VERSION_STRING="version: $NEW_FULL_VERSION"
echo "NEW_VERSION_STRING = $NEW_VERSION_STRING"

# Modify yaml
$SED -i "s/${VERSION_STRING}/${NEW_VERSION_STRING}/g" $YAML_FILE

# Modify Snap
$SED -i "s/version: ${OLD_VERSION}/version: ${NEW_VERSION}/g" $SNAP_YAML_FILE
$SED -i "s/Version=${OLD_VERSION}/Version=${NEW_VERSION}/g" $SNAP_DESKTOP_FILE

# Modify Debian
$SED -i "s/Version: ${OLD_VERSION}/Version: ${NEW_VERSION}/g" $DEBIAN_YAML_FILE
$SED -i "s/Version=${OLD_VERSION}/Version=${NEW_VERSION}/g" $DEBIAN_DESKTOP_FILE

# Modify Qt
OLD_FILEVERSION="$MAJOR_NUMBER,$MINOR_NUMBER,$OLD_PATCH_NUMBER"
FILEVERSION="$MAJOR_NUMBER,$MINOR_NUMBER,$PATCH_NUMBER"
$SED -i "s/${OLD_FILEVERSION},0/${FILEVERSION},0/g" $QT_RC_FILE
$SED -i "s/${OLD_VERSION}.0/${NEW_VERSION}.0/g" $QT_RC_FILE

# Changelog
rm -f ${BUILD_NUMBER}.txt
touch ${BUILD_NUMBER}.txt

echo "v$NEW_VERSION" >> ${BUILD_NUMBER}.txt
echo >> ${BUILD_NUMBER}.txt

for DIR in "${CHANGELOG_DIRS[@]}"; do
  mkdir -p $DIR || true
  cp ${BUILD_NUMBER}.txt $DIR
  case $DIR in
    *ar*) echo "يتضمن هذا التحديث تحسينات وإصلاحات للأخطاء لجعل التطبيق أفضل بالنسبة لك." >> $DIR/${BUILD_NUMBER}.txt ;;
    *bg*) echo "Това актуализиране включва различни подобрения и корекции на грешки, за да направи приложението по-добро за вас." >> $DIR/${BUILD_NUMBER}.txt ;;
    *bo*) echo "ད་དུང་འདི་ལག་ཐོག་སྤུན་རྒྱུད་བཟོ་བཅོས་དང་བདག་སྤྱོད་གཏོང་མཁན་སོགས་ནང་འཁོད་དང་འབྲི་གཏོང་མཁན་སྔར་བཞིན་གཞན་དང་མཉམ་འབྲི་འདུག་གས།" >> $DIR/${BUILD_NUMBER}.txt ;;
    *cs-CZ*) echo "Tato aktualizace obsahuje různá vylepšení a opravy chyb, aby byla aplikace pro vás lepší." >> $DIR/${BUILD_NUMBER}.txt ;;
    *de-DE*) echo "Dieses Update umfasst verschiedene Verbesserungen und Fehlerbehebungen, um die App für dich zu verbessern." >> $DIR/${BUILD_NUMBER}.txt ;;
    *en-US*) echo "This update includes various improvements and bug fixes to make the app better for you." >> $DIR/${BUILD_NUMBER}.txt ;;
    *es-ES*) echo "Esta actualización incluye varias mejoras y correcciones de errores para mejorar la aplicación para ti." >> $DIR/${BUILD_NUMBER}.txt ;;
    *fa-IR*) echo "این به‌روزرسانی شامل بهبودها و رفع اشکالات مختلفی است که برنامه را برای شما بهتر می‌کند." >> $DIR/${BUILD_NUMBER}.txt ;;
    *fr*) echo "Cette mise à jour comprend diverses améliorations et corrections de bugs pour améliorer l'application pour vous." >> $DIR/${BUILD_NUMBER}.txt ;;
    *gu*) echo "આ અપડેટમાં વિવિધ સુધારાઓ અને બગ ફિક્સનો સમાવેશ થાય છે જે એપ્લિકેશનને તમારા માટે વધુ સારું બનાવે છે." >> $DIR/${BUILD_NUMBER}.txt ;;
    *he*) echo "עדכון זה כולל שיפורים ותיקוני באגים שונים כדי להפוך את האפליקציה לטובה יותר עבורך." >> $DIR/${BUILD_NUMBER}.txt ;;
    *hi-IN*) echo "इस अपडेट में विभिन्न सुधार और बग फिक्स शामिल हैं जो ऐप को आपके लिए बेहतर बनाते हैं।" >> $DIR/${BUILD_NUMBER}.txt ;;
    *hr*) echo "Ovo ažuriranje uključuje razna poboljšanja i ispravke pogrešaka kako bi aplikacija bila bolja za vas." >> $DIR/${BUILD_NUMBER}.txt ;;
    *hu-HU*) echo "Ez a frissítés különféle fejlesztéseket és hibajavításokat tartalmaz, hogy jobbá tegye az alkalmazást az Ön számára." >> $DIR/${BUILD_NUMBER}.txt ;;
    *is-IS*) echo "Þessi uppfærsla inniheldur ýmsar endurbætur og villuleiðréttingar til að gera forritið betra fyrir þig." >> $DIR/${BUILD_NUMBER}.txt ;;
    *it-IT*) echo "Questo aggiornamento include vari miglioramenti e correzioni di bug per rendere l'app migliore per te." >> $DIR/${BUILD_NUMBER}.txt ;;
    *ja-JP*) echo "このアップデートには、アプリをより良くするためのさまざまな改善とバグ修正が含まれています。" >> $DIR/${BUILD_NUMBER}.txt ;;
    *ko*) echo "이번 업데이트에는 다양한 개선 사항과 버그 수정이 포함되어 있어 앱을 더 잘 사용할 수 있습니다." >> $DIR/${BUILD_NUMBER}.txt ;;
    *pl-PL*) echo "Ta aktualizacja zawiera różne ulepszenia i poprawki błędów, aby aplikacja była lepsza dla ciebie." >> $DIR/${BUILD_NUMBER}.txt ;;
    *ru*) echo "Это обновление включает в себя различные улучшения и исправления ошибок, чтобы сделать приложение лучше для вас." >> $DIR/${BUILD_NUMBER}.txt ;;
    *sq*) echo "Ky përditësim përfshin përmirësime dhe riparime të ndryshme për ta bërë aplikacionin më të mirë për ju." >> $DIR/${BUILD_NUMBER}.txt ;;
    *sr*) echo "Ovo ažuriranje uključuje razna poboljšanja i ispravke pogrešaka kako bi aplikacija bila bolja za vas." >> $DIR/${BUILD_NUMBER}.txt ;;
    *sv*) echo "Denna uppdatering inkluderar olika förbättringar och buggfixar för att göra appen bättre för dig." >> $DIR/${BUILD_NUMBER}.txt ;;
    *tr-TR*) echo "Bu güncelleme, uygulamayı sizin için daha iyi hale getirmek için çeşitli iyileştirmeler ve hata düzeltmeleri içerir." >> $DIR/${BUILD_NUMBER}.txt ;;
    *uk*) echo "Це оновлення включає різні покращення та виправлення помилок, щоб зробити додаток кращим для вас." >> $DIR/${BUILD_NUMBER}.txt ;;
    *zh-CN*) echo "此更新包括各种改进和错误修复，以使本 App 更好用。" >> $DIR/${BUILD_NUMBER}.txt ;;
    *zh-TW*) echo "此更新包括各種改進和錯誤修復，以使本 App 更好用。" >> $DIR/${BUILD_NUMBER}.txt ;;
  esac
  #$EDITOR $DIR/${BUILD_NUMBER}.txt
done

# Git commit
git status -s
git add .
git commit -m "Sanmill v$NEW_VERSION (${BUILD_NUMBER})" -m "Official release version of Sanmill v$NEW_VERSION"
#exit
git tag -d v$NEW_VERSION || true
git tag -m "Sanmill v$NEW_VERSION (${BUILD_NUMBER})" -m "Official release version of Sanmill v$NEW_VERSION" v$NEW_VERSION

# Show the latest commit details
git show

# Prompt the user for confirmation
read -p "Do you want to push the latest changes to the master branch? (y/n): " choice

if [ "$choice" == "y" ]; then
  # If the user confirms, push the changes to the master branch
  git push origin v$NEW_VERSION -f
  git push origin master
  echo "Changes have been pushed to the master branch."
else
  # If the user declines, skip the push
  echo "Push to master branch has been skipped."
fi
