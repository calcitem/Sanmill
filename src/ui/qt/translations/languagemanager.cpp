// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// languagemanager.cpp

#include "languagemanager.h"
#include <QCoreApplication>
#include <QDir>
#include <QDebug>

LanguageManager* LanguageManager::m_instance = nullptr;

LanguageManager* LanguageManager::getInstance()
{
    if (!m_instance) {
        m_instance = new LanguageManager();
    }
    return m_instance;
}

LanguageManager::LanguageManager(QObject *parent)
    : QObject(parent)
    , m_translator(new QTranslator(this))
    , m_currentLanguage(English)
{
    loadLanguageSettings();
}

LanguageManager::~LanguageManager()
{
    if (m_translator) {
        QCoreApplication::removeTranslator(m_translator);
    }
}

void LanguageManager::loadLanguage(Language language)
{
    if (m_currentLanguage == language) {
        return;
    }

    // Remove current translator
    if (m_translator) {
        QCoreApplication::removeTranslator(m_translator);
        m_translator->deleteLater();
    }

    // Create new translator
    m_translator = new QTranslator(this);
    
    QString languageCode = getLanguageCode(language);
    QString translationFile = QString("mill-pro_%1").arg(languageCode);
    
    // Try to load from resources first
    QString resourcePath = QString(":/translations/%1").arg(translationFile);
    bool loaded = m_translator->load(resourcePath);
    
    if (!loaded) {
        // Try to load from local translations directory
        QString localPath = QString("translations/%1").arg(translationFile);
        loaded = m_translator->load(localPath);
    }
    
    if (!loaded) {
        // Try to load from current directory
        loaded = m_translator->load(translationFile);
    }

    if (loaded) {
        QCoreApplication::installTranslator(m_translator);
        m_currentLanguage = language;
        saveLanguageSettings();
        emit languageChanged();
        qDebug() << "Language loaded successfully:" << languageCode;
    } else {
        qWarning() << "Failed to load translation file for language:" << languageCode;
        // Keep using previous language if loading fails
        if (m_currentLanguage != English) {
            loadLanguage(English); // Fallback to English
        }
    }
}

void LanguageManager::loadLanguage(const QString& languageCode)
{
    Language language = getLanguageFromCode(languageCode);
    loadLanguage(language);
}

LanguageManager::Language LanguageManager::getCurrentLanguage() const
{
    return m_currentLanguage;
}

QString LanguageManager::getCurrentLanguageCode() const
{
    return getLanguageCode(m_currentLanguage);
}

QString LanguageManager::getLanguageName(Language language) const
{
    switch (language) {
    case English:
        return "English";
    case German:
        return "Deutsch";
    case Hungarian:
        return "Magyar";
    case SimplifiedChinese:
        return "Simplified Chinese";
    default:
        return "English";
    }
}

QStringList LanguageManager::getAvailableLanguages() const
{
    QStringList languages;
    languages << getLanguageName(English)
              << getLanguageName(German)
              << getLanguageName(Hungarian)
              << getLanguageName(SimplifiedChinese);
    return languages;
}

QStringList LanguageManager::getAvailableLanguageCodes() const
{
    QStringList codes;
    codes << getLanguageCode(English)
          << getLanguageCode(German)
          << getLanguageCode(Hungarian)
          << getLanguageCode(SimplifiedChinese);
    return codes;
}

void LanguageManager::saveLanguageSettings()
{
    QSettings settings;
    settings.setValue("language", getLanguageCode(m_currentLanguage));
}

void LanguageManager::loadLanguageSettings()
{
    QSettings settings;
    QString languageCode = settings.value("language", "en").toString();
    m_currentLanguage = getLanguageFromCode(languageCode);
}

QString LanguageManager::getLanguageCode(Language language) const
{
    switch (language) {
    case English:
        return "en";
    case German:
        return "de";
    case Hungarian:
        return "hu";
    case SimplifiedChinese:
        return "zh_CN";
    default:
        return "en";
    }
}

LanguageManager::Language LanguageManager::getLanguageFromCode(const QString& code) const
{
    if (code == "de") return German;
    if (code == "hu") return Hungarian;
    if (code == "zh_CN") return SimplifiedChinese;
    return English; // Default to English
} 