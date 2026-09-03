#include "translator.hpp"

#include <QCoreApplication>
#include <QQmlEngine>

Translator::Translator(QObject* parent): QObject(parent) {}

bool Translator::load(const QString& catalogPath) {
    QCoreApplication::removeTranslator(&m_translator);

    if (!m_translator.load(catalogPath)) return false;
    if (!QCoreApplication::installTranslator(&m_translator)) return false;

    if (auto* engine = qmlEngine(this)) engine->retranslate();

    return true;
}
