// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// languagemanager.h

#ifndef LANGUAGEMANAGER_H
#define LANGUAGEMANAGER_H

#include <QObject>
#include <QTranslator>
#include <QApplication>
#include <QSettings>

class LanguageManager : public QObject
{
    Q_OBJECT

public:
    enum Language {
        English = 0,
        German,
        Hungarian,
        SimplifiedChinese
    };

    static LanguageManager* getInstance();
    void loadLanguage(Language language);
    void loadLanguage(const QString& languageCode);
    Language getCurrentLanguage() const;
    QString getCurrentLanguageCode() const;
    QString getLanguageName(Language language) const;
    QStringList getAvailableLanguages() const;
    QStringList getAvailableLanguageCodes() const;
    
    // Initialize language with settings file path
    void initializeWithSettingsFile(const QString& settingsPath);
    
    // Load language from settings and apply it
    void loadAndApplyLanguageFromSettings();

signals:
    void languageChanged();

private:
    explicit LanguageManager(QObject *parent = nullptr);
    ~LanguageManager();
    
    static LanguageManager* m_instance;
    QTranslator* m_translator;
    Language m_currentLanguage;
    QString m_settingsFilePath;  // Store settings file path
    
    void saveLanguageSettings();
    void loadLanguageSettings();
    QString getLanguageCode(Language language) const;
    Language getLanguageFromCode(const QString& code) const;
};

#endif // LANGUAGEMANAGER_H 