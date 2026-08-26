# frozen_string_literal: true

# Licensed to the Software Freedom Conservancy (SFC) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The SFC licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

# Shared generated-file marker text for Ruby generators — see scripts/generated_note_template.txt.
module GeneratedNote
  def self.runfiles
    @runfiles ||= begin
      require 'bazel/runfiles'
      Bazel::Runfiles.create
    end
  end

  # Resolves a Bazel rlocation key to a real path. Under Bazel, uses the runfiles
  # tree. Off Bazel (aeb build), falls back to a repo-root-relative path derived
  # from the key (which is of the form \"_main/<repo-relative-path>\"). The
  # Bazel-runfiles path is kept so this still works during the Bazel->aeb
  # coexistence window; the fallback is what an aeb build uses.
  def self.rlocation(key)
    begin
      p = runfiles.rlocation(key)
      return p if p
    rescue LoadError
      # bazel/runfiles gem absent (not running under Bazel) - fall through.
    end
    # key looks like \"_main/scripts/generated_note_template.txt\"; strip the
    # leading \"_main/\" and resolve against the repo root (four dirs up from
    # rb/support/generated_note.rb: rb/support -> rb -> <repo root>).
    rel = key.start_with?("_main/") ? key[("_main/".length)..] : key
    repo_root = File.expand_path("../..", __dir__)
    path = File.join(repo_root, rel)
    File.exist?(path) ? path : raise("Could not resolve #{key.inspect} (tried Bazel runfiles and #{path})")
  end

  # Renders the standard two-line generated-file marker in the given comment style.
  def self.render(comment_prefix, generator, command)
    template = File.read(rlocation('_main/scripts/generated_note_template.txt'))
    text = template.sub('{generator}', generator).sub('{command}', command)
    text.rstrip.split("\n").map { |line| "#{comment_prefix} #{line}" }.join("\n")
  end
end
