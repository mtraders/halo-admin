<template>
  <page-view
    :sub-title="postToStage.inProgress ? '当前内容已保存，但还未发布。' : ''"
    :title="postToStage.title ? postToStage.title : '新文章'"
    affix
  >
    <template slot="extra">
      <a-space>
        <a-button :loading="previewSaving" @click="handlePreviewClick">预览</a-button>
        <a-button type="primary" @click="postSettingVisible = true">发布</a-button>
      </a-space>
    </template>
    <a-row :gutter="12">
      <a-col :span="24">
        <div class="mb-4">
          <a-input v-model="postToStage.title" placeholder="请输入文章标题" size="large" />
        </div>
        <div id="editor">
          <div style="border: 1px solid #ccc">
            <Toolbar
              style="border-bottom: 1px solid #ccc"
              :editor="editor"
              :mode="mode"
              :defaultConfig="toolbarConfig"
            />
            <Editor
              style="height: 700px; overflow-y: hidden"
              v-model="postToStage.originalContent"
              :defaultConfig="editorConfig"
              :mode="mode"
              @onCreated="onCreated"
              @onChange="onContentChange"
            />
          </div>
        </div>
      </a-col>
    </a-row>

    <PostSettingModal
      :post="postToStage"
      :savedCallback="onPostSavedCallback"
      :visible.sync="postSettingVisible"
      @onUpdate="onUpdateFromSetting"
    />
  </page-view>
</template>

<script>
// components
import PostSettingModal from '../../components/Post/PostSettingModal'
import '@wangeditor/editor/dist/css/style.css'
import { Editor, Toolbar } from '@wangeditor/editor-for-vue'
import { PageView } from '@/layouts'

// libs
import { mixin, mixinDevice, mixinPostEdit } from '@/mixins/mixin.js'
import { datetimeFormat } from '@/utils/datetime'
import apiClient from '@/utils/api-client'
import debounce from 'lodash.debounce'

export default {
  mixins: [mixin, mixinDevice, mixinPostEdit],
  components: {
    PostSettingModal,
    Editor,
    Toolbar,
    PageView
  },
  data() {
    return {
      editor: null,
      postSettingVisible: false,
      postToStage: {
        editorType: 'RICHTEXT',
        keepRaw: true
      },
      contentChanges: 0,
      previewSaving: false,
      toolbarConfig: {
        insertKeys: {
          index: 22, // 自定义插入的位置
          keys: ['uploadAttachment'] // “上传附件”菜单
        }
      },
      editorConfig: {
        placeholder: '请输入内容...',
        MENU_CONF: {
          uploadImage: {
            server: '/api/admin/attachments/upload',
            customUpload: this.handleCustomUploadImage
          },
          uploadVideo: {
            server: '/api/admin/attachments/upload',
            customUpload: this.handleCustomUploadVideo
          },
          uploadAttachment: {
            server: '/api/admin/attachments/upload',
            customUpload: this.handleCustomUploadAttachment
          }
        }
      },
      mode: 'default'
    }
  },
  beforeRouteEnter(to, from, next) {
    // Get post id from query
    const postId = to.query.postId
    next(async vm => {
      if (postId) {
        const { data } = await apiClient.post.get(Number(postId))
        vm.postToStage = data
      }
    })
  },
  destroyed() {
    if (window.onbeforeunload) {
      window.onbeforeunload = null
    }
  },
  beforeRouteLeave(to, from, next) {
    if (this.contentChanges <= 1) {
      next()
    } else {
      this.$confirm({
        title: '当前页面数据未保存，确定要离开吗？',
        content: () => <div style="color:red;">如果离开当面页面，你的数据很可能会丢失！</div>,
        onOk() {
          next()
        },
        onCancel() {
          next(false)
        }
      })
    }
  },
  mounted() {
    window.onbeforeunload = function (e) {
      e = e || window.event
      if (e) {
        e.returnValue = '当前页面数据未保存，确定要离开吗？'
      }
      return '当前页面数据未保存，确定要离开吗？'
    }
  },
  beforeMount() {
    document.addEventListener('keydown', this.onRegisterSaveShortcut)
  },
  beforeDestroy() {
    const editor = this.editor
    if (editor == null) return
    editor.destroy()
    document.removeEventListener('keydown', this.onRegisterSaveShortcut)
  },
  methods: {
    onCreated(editor) {
      this.editor = Object.seal(editor)
    },
    onRegisterSaveShortcut(e) {
      if ((e.ctrlKey || e.metaKey) && !e.altKey && !e.shiftKey && e.keyCode === 83) {
        e.preventDefault()
        e.stopPropagation()
        this.handleSaveDraft()
      }
    },

    handleSaveDraft: debounce(async function () {
      if (this.postToStage.id) {
        // Update the post content
        try {
          const { data } = await apiClient.post.updateDraftById(
            this.postToStage.id,
            this.postToStage.originalContent,
            this.postToStage.content,
            true
          )
          this.postToStage.inProgress = data.inProgress
          this.handleRestoreSavedStatus()
          this.$message.success({
            content: '内容已保存',
            duration: 0.5
          })
        } catch (e) {
          this.$log.error('Failed to update post content', e)
        }
      } else {
        await this.handleCreatePost()
      }
    }, 300),

    async handleCreatePost() {
      if (!this.postToStage.title) {
        this.postToStage.title = datetimeFormat(new Date(), 'YYYY-MM-DD-HH-mm-ss')
      }
      // Create the post
      try {
        this.postToStage.keepRaw = true

        const { data } = await apiClient.post.create(this.postToStage)
        this.postToStage = data
        this.handleRestoreSavedStatus()

        // add params to url
        const path = this.$router.history.current.path
        this.$router.push({ path, query: { postId: this.postToStage.id } }).catch(err => err)

        this.$message.success({
          content: '文章已创建',
          duration: 0.5
        })
      } catch (e) {
        this.$log.error('Failed to create post', e)
      }
    },

    async handlePreviewClick() {
      this.previewSaving = true
      if (this.postToStage.id) {
        // Update the post content
        const { data } = await apiClient.post.updateDraftById(
          this.postToStage.id,
          this.postToStage.originalContent,
          this.postToStage.content,
          true
        )
        this.postToStage.inProgress = data.inProgress
      } else {
        await this.handleCreatePost()
      }
      await this.handleOpenPreview()
    },

    async handleOpenPreview() {
      try {
        const response = await apiClient.post.getPreviewLinkById(this.postToStage.id)
        window.open(response, '_blank')
        this.handleRestoreSavedStatus()
      } catch (e) {
        this.$log.error('Failed to get preview link', e)
      } finally {
        setTimeout(() => {
          this.previewSaving = false
        }, 400)
      }
    },

    handleRestoreSavedStatus() {
      this.contentChanges = 0
    },
    onContentChange(editor) {
      this.contentChanges++
      this.postToStage.content = editor.getText()
    },
    onPostSavedCallback() {
      this.contentChanges = 0
      this.$router.push({ name: 'PostList' })
    },
    onUpdateFromSetting(post) {
      this.postToStage = post
    },
    handleCustomUploadImage(file, insertFn) {
      apiClient.attachment
        .upload(file)
        .then(response => {
          const attachment = response.data
          insertFn(`https://cern-api.fists.cn${attachment.path}`)
        })
        .catch(e => {
          this.$log.error('upload image error: ', e)
        })
    },
    handleCustomUploadVideo(file, insertFn) {
      apiClient.attachment
        .upload(file)
        .then(response => {
          const attachment = response.data
          insertFn(`https://cern-api.fists.cn${attachment.path}`)
        })
        .catch(e => {
          this.$log.error('upload video error: ', e)
        })
    },
    handleCustomUploadAttachment(file, insertFn) {
      apiClient.attachment
        .upload(file)
        .then(response => {
          const attachment = response.data
          insertFn(`https://cern-api.fists.cn${attachment.path}`, `${attachment.name}`)
        })
        .catch(e => {
          this.$log.error('upload attachment error: ', e)
        })
    }
  }
}
</script>
