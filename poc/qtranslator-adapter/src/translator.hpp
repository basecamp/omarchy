#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QTranslator>

class Translator final : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit Translator(QObject* parent = nullptr);

    Q_INVOKABLE bool load(const QString& catalogPath);

private:
    QTranslator m_translator;
};
