// Copyright (c) 2013, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

/**
 * A library to manage the list of open editors, and persist their state (like
 * their selection and scroll position) across sessions.
 */
library spark.editors;

import 'dart:async';
import 'dart:convert' show JSON;

import 'ace.dart';
import 'preferences.dart';
import 'workspace.dart';

/**
 * Manage a list of open editors.
 */
class EditorManager {
  Workspace _workspace;
  AceEditor _aceEditor;
  PreferenceStore _prefs;
  List<_EditorState> _editorStates = [];
  _EditorState _currentState;
  StreamController<File> _streamController = new StreamController.broadcast();

  EditorManager(this._workspace, this._aceEditor, this._prefs) {
    _prefs.getValue('editorStates').then((String data) {
      if (data != null) {
        for (Map m in JSON.decode(data)) {
          _editorStates.add(new _EditorState.fromMap(_workspace, m));
        }
      }
    });
  }

  File get currentFile => _currentState != null ? _currentState.file : null;

  Stream<File> get onFileChange => _streamController.stream;

  bool get dirty => _currentState == null ? false : _currentState.dirty;

  void select(File file) {
    _EditorState state = _getStateFor(file);

    if (state == null) {
      state = new _EditorState.fromFile(file);
      _editorStates.add(state);
    }

    _showState(state);
  }

  void save() {
    // TODO: I'm not sure we need this method -
    if (_currentState != null) {
      _currentState.file.setContents(_currentState.session.value);
      _currentState.dirty = false;
    }
  }

  void close(File file) {
    _EditorState state = _getStateFor(file);

    if (state != null) {
      int index = _editorStates.indexOf(state);
      _editorStates.remove(state);

      if (_currentState == state) {
        // Switch to the next editor.
        if (_editorStates.isEmpty) {
          _switchState(null);
        } else if (index < _editorStates.length){
          _switchState(_editorStates[index]);
        } else {
          _switchState(_editorStates[index - 1]);
        }
      }
    }
  }

  void persistState() {
    var stateData = _editorStates.map((state) => state.toMap());
    _prefs.setValue('editorStates', JSON.encode(stateData));
  }

  _EditorState _getStateFor(File file) {
    for (_EditorState state in _editorStates) {
      if (state.file == file) {
        return state;
      }
    }

    return null;
  }

  void _showState(_EditorState state) {
    _currentState = state;

    if (state != null) {
      if (state.session != null) {
        _aceEditor.switchTo(state.session);
      } else {
        state.realize().then((_) {
          _aceEditor.switchTo(state.session);
        });
      }
    } else {
      _switchState(state);
    }
  }

  void _switchState(_EditorState state) {
    if (_currentState != state) {
      _currentState = state;
      _streamController.add(currentFile);
      _aceEditor.switchTo(state == null ? null : state.session);
    }
  }
}

class _EditorState {
  File file;
  EditSession session;
  int scrollTop = 0;
  bool dirty = false;

  _EditorState.fromFile(this.file);

  _EditorState.fromMap(Workspace workspace, Map m) {
    file = workspace.restoreFromToken(m['file']);
    scrollTop = m['scrollTop'];
  }

  Map toMap() {
    Map m = {};
    m['file'] = file.persistToToken();
    m['scrollTop'] = session == null ? scrollTop : session.scrollTop;
    return m;
  }

  Future<_EditorState> realize() {
    return file.getContents().then((text) {
      session = AceEditor.createEditSession(text, file.name);
      session.scrollTop = scrollTop;
      session.onChange.listen((delta) => dirty = true);
      return this;
    });
  }
}
