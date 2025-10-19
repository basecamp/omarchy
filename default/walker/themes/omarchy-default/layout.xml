<?xml version="1.0" encoding="UTF-8"?>
<interface>
  <requires lib="gtk" version="4.0"></requires>
  <object class="GtkWindow" id="Window">
    <style>
      <class name="window"></class>
    </style>
    <property name="resizable">true</property>
    <property name="title">Walker</property>
    <child>
      <object class="GtkBox" id="BoxWrapper">
        <style>
          <class name="box-wrapper"></class>
        </style>
        <property name="width-request">644</property>
        <property name="overflow">hidden</property>
        <property name="orientation">horizontal</property>
        <property name="valign">center</property>
        <property name="halign">center</property>
        <child>
          <object class="GtkBox" id="Box">
            <style>
              <class name="box"></class>
            </style>
            <property name="orientation">vertical</property>
            <property name="hexpand-set">true</property>
            <property name="hexpand">true</property>
            <property name="spacing">10</property>
            <child>
              <object class="GtkBox" id="SearchContainer">
                <style>
                  <class name="search-container"></class>
                </style>
                <property name="overflow">hidden</property>
                <property name="orientation">horizontal</property>
                <property name="halign">fill</property>
                <property name="hexpand-set">true</property>
                <property name="hexpand">true</property>
                <child>
                  <object class="GtkEntry" id="Input">
                    <style>
                      <class name="input"></class>
                    </style>
                    <property name="halign">fill</property>
                    <property name="hexpand-set">true</property>
                    <property name="hexpand">true</property>
                  </object>
                </child>
              </object>
            </child>
            <child>
              <object class="GtkBox" id="ContentContainer">
                <style>
                  <class name="content-container"></class>
                </style>
                <property name="orientation">horizontal</property>
                <property name="spacing">10</property>
                <property name="vexpand">true</property>
                <property name="vexpand-set">true</property>
                <child>
                  <object class="GtkLabel" id="ElephantHint">
                    <style>
                      <class name="elephant-hint"></class>
                    </style>
                    <property name="hexpand">true</property>
                    <property name="height-request">100</property>
                    <property name="label">Waiting for elephant...</property>
                  </object>
                </child>
                <child>
                  <object class="GtkLabel" id="Placeholder">
                    <style>
                      <class name="placeholder"></class>
                    </style>
                    <property name="label">No Results</property>
                    <property name="yalign">0.0</property>
                    <property name="hexpand">true</property>
                  </object>
                </child>
                <child>
                  <object class="GtkScrolledWindow" id="Scroll">
                    <style>
                      <class name="scroll"></class>
                    </style>
                    <property name="hexpand">true</property>
                    <property name="can_focus">false</property>
                    <property name="overlay-scrolling">true</property>
                    <property name="max-content-width">600</property>
                    <property name="max-content-height">300</property>
                    <property name="min-content-height">0</property>
                    <property name="propagate-natural-height">true</property>
                    <property name="propagate-natural-width">true</property>
                    <property name="hscrollbar-policy">automatic</property>
                    <property name="vscrollbar-policy">automatic</property>
                    <child>
                      <object class="GtkGridView" id="List">
                        <style>
                          <class name="list"></class>
                        </style>
                        <property name="max_columns">1</property>
                        <property name="can_focus">false</property>
                      </object>
                    </child>
                  </object>
                </child>
                <child>
                  <object class="GtkBox" id="Preview">
                    <style>
                      <class name="preview"></class>
                    </style>
                  </object>
                </child>
              </object>
            </child>
            <child>
              <object class="GtkLabel" id="Error">
                <style>
                  <class name="error"></class>
                </style>
                <property name="xalign">0</property>
               <property name="visible">false</property>
              </object>
            </child>
          </object>
        </child>
      </object>
    </child>
  </object>
</interface>
