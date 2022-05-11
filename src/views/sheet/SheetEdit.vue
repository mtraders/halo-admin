<template>
  <page-view
    :sub-title="sheetToStage.inProgress ? '当前内容已保存，但还未发布。' : ''"
    :title="sheetToStage.title ? sheetToStage.title : '新页面'"
    affix
  >
    <template slot="extra">
      <a-space>
        <a-button :loading="previewSaving" @click="handlePreviewClick">预览</a-button>
        <a-button type="primary" @click="sheetSettingVisible = true">发布</a-button>
      </a-space>
    </template>
    <a-row :gutter="12">
      <a-col :span="24">
        <div class="mb-4">
          <a-input v-model="sheetToStage.title" placeholder="请输入页面标题" size="large" />
        </div>

        <div id="editor">
          <Toolbar style="border-bottom: 1px solid #ccc" :editor="editor" :mode="mode" :defaultConfig="toolbarConfig" />
          <Editor
            style="height: 700px; overflow-y: hidden"
            v-model="sheetToStage.originalContent"
            :defaultConfig="editorConfig"
            :mode="mode"
            @onCreated="onCreated"
            @onChange="onContentChange"
          />
        </div>
      </a-col>
    </a-row>

    <SheetSettingModal
      :sheet="sheetToStage"
      :savedCallback="onSheetSavedCallback"
      :visible.sync="sheetSettingVisible"
      @onUpdate="onUpdateFromSetting"
    />
  </page-view>
</template>

<script>
// components
import { PageView } from '@/layouts'
import SheetSettingModal from './components/SheetSettingModal'
import '@wangeditor/editor/dist/css/style.css'
import { Editor, Toolbar } from '@wangeditor/editor-for-vue'

// libs
import { mixin, mixinDevice, mixinPostEdit } from '@/mixins/mixin.js'
import { datetimeFormat } from '@/utils/datetime'
import apiClient from '@/utils/api-client'
import debounce from 'lodash.debounce'

export default {
  components: {
    PageView,
    SheetSettingModal,
    Editor,
    Toolbar
  },
  mixins: [mixin, mixinDevice, mixinPostEdit],
  data() {
    return {
      editor: null,
      sheetSettingVisible: false,
      sheetToStage: {
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
    // Get sheetId id from query
    const sheetId = to.query.sheetId

    next(async vm => {
      if (sheetId) {
        const { data } = await apiClient.sheet.get(Number(sheetId))
        vm.sheetToStage = data
      }
    })
  },
  destroyed: function () {
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
      if (this.sheetToStage.id) {
        try {
          const { data } = await apiClient.sheet.updateDraftById(
            this.sheetToStage.id,
            this.sheetToStage.originalContent,
            this.sheetToStage.content,
            true
          )
          this.sheetToStage.inProgress = data.inProgress
          this.handleRestoreSavedStatus()
          this.$message.success({
            content: '内容已保存',
            duration: 0.5
          })
        } catch (e) {
          this.$log.error('Failed to update sheet content', e)
        }
      } else {
        await this.handleCreateSheet()
      }
    }, 300),

    async handleCreateSheet() {
      if (!this.sheetToStage.title) {
        this.sheetToStage.title = datetimeFormat(new Date(), 'YYYY-MM-DD-HH-mm-ss')
      }
      try {
        this.sheetToStage.keepRaw = true
        const { data } = await apiClient.sheet.create(this.sheetToStage)
        this.sheetToStage = data
        this.handleRestoreSavedStatus()

        // add params to url
        const path = this.$router.history.current.path
        this.$router.replace({ path, query: { sheetId: this.sheetToStage.id } }).catch(err => err)
        this.$message.success({
          content: '页面已创建',
          duration: 0.5
        })
      } catch (e) {
        this.$log.error('Failed to create sheet', e)
      }
    },

    async handlePreviewClick() {
      this.previewSaving = true
      if (this.sheetToStage.id) {
        // Update the sheet content
        const { data } = await apiClient.sheet.updateDraftById(
          this.sheetToStage.id,
          this.sheetToStage.originalContent,
          this.sheetToStage.content,
          true
        )
        this.sheetToStage.inProgress = data.inProgress
      } else {
        await this.handleCreateSheet()
      }
      await this.handleOpenPreview()
    },

    async handleOpenPreview() {
      try {
        const response = await apiClient.sheet.getPreviewLinkById(this.sheetToStage.id)
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
    onContentChange({ originalContent, renderContent }) {
      this.contentChanges++
      this.sheetToStage.originalContent = originalContent
      this.sheetToStage.content = renderContent
    },
    onSheetSavedCallback() {
      this.contentChanges = 0
      this.$router.push({ name: 'SheetList', query: { activeKey: 'custom' } })
    },
    onUpdateFromSetting(sheet) {
      this.sheetToStage = sheet
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
          this.$log.error('upload image error: ', e)
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
